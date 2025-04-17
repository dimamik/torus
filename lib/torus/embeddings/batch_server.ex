defmodule Torus.Embeddings.Batcher do
  @moduledoc """
  Size/time‑bounded **batcher** for embedding generation.

  `Torus.Embeddings.Batcher` is a long‑running GenServer that collects
  individual `generate/2` calls, groups them into a single batch, and forwards the
  batch to the configured `embedding_module`.

  ---

  ## Why batch?

  * **Fewer model / network invocations** – one request with *n* terms is cheaper
  than *n* single‑term requests.
  * **Lower latency under load** – callers wait only for the current batch to
  flush, not for an entire queue of independent requests.
  * **Higher throughput per API quota** – most providers charge per request, so
  batched calls extract more value from the same quota.

  ---

  ## Flush conditions

  A batch is flushed when **either** condition is met (whichever comes first):

  * the queue reaches `max_batch_size` terms, or
  * `max_batch_wait_ms` elapses after the first term was queued.

  Both limits are fully configurable.

  ---

  ## Configuration

  It's considered a good practise to batch requests to the embedding module, especially when you are dealing with a high-traffic applications.

  To use it:

  - Add the following to your `config.exs`:

  ```elixir
   config :torus, batcher: Torus.Embeddings.Batcher

   config :torus, Torus.Embeddings.Batcher,
      max_batch_size: 10,
      default_batch_timeout: 100,
      embedding_module: Torus.Embeddings.HuggingFace
  ```

  - Add it to your supervision tree:

  ```elixir
  def start(_type, _args) do
    children = [
      # Your deps
      Torus.Embeddings.Batcher
    ]

    opts = [strategy: :one_for_one, name: YourApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
  ```

  - Configure your `embedding_module` of choice (see corresponding section)

  And you should be good to call `Torus.to_vector/1` and `Torus.to_vectors/1` functions.

  Also, you can configure `call_timeout` option in `Torus.to_vector/2` and `Torus.to_vectors/2` functions to override the default timeout for the batching call. This is useful if you're okay to wait longer for the batch to flush and your embedder to generate the embedding.

  See `Torus.semantic/5` on how to use this module to introduce semantic search in your application.
  """

  use GenServer
  @behaviour Torus.Embedding

  alias Torus.Embeddings.Common

  @default_max_batch_size 10
  @default_batch_timeout 100
  @call_timeout @default_batch_timeout * 100

  ## Public API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def generate(terms, opts \\ []) do
    GenServer.call(__MODULE__, {:embed, terms}, opts[:timeout] || @call_timeout)
  end

  def embedding_model(opts \\ []) do
    module = embedding_module(opts)
    module.embedding_model(opts)
  end

  ## GenServer Callbacks

  def init(opts \\ []) do
    {:ok,
     %{
       max_batch_size:
         Common.get_option(opts, __MODULE__, :max_batch_size, @default_max_batch_size),
       batch_timeout: Common.get_option(opts, __MODULE__, :batch_timeout, @default_batch_timeout),
       embedding_module: embedding_module(opts),
       queue: [],
       timer: nil
     }}
  end

  def handle_call({:embed, terms}, from, %{queue: queue} = state) do
    new_queue = queue ++ [{terms, from}]

    # Start timer only if queue was previously empty
    new_state =
      if Enum.empty?(queue) do
        %{state | queue: new_queue, timer: start_timer(state.batch_timeout)}
      else
        %{state | queue: new_queue}
      end

    maybe_flush(new_state)
  end

  def handle_info(:flush, state) do
    flush_batch(state)
    {:noreply, %{state | queue: [], timer: nil}}
  end

  ## Helpers

  defp maybe_flush(%{queue: queue, max_batch_size: max_batch_size} = state)
       when length(queue) >= max_batch_size do
    cancel_timer(state.timer)
    flush_batch(state)
    {:noreply, %{state | queue: [], timer: nil}}
  end

  defp maybe_flush(state), do: {:noreply, state}

  defp flush_batch(%{queue: queue, embedding_module: embedder}) do
    # Step 1: Gather all terms and count how many each caller sent
    {flattened_terms, term_counts} =
      Enum.reduce(queue, {[], []}, fn {terms, _from}, {acc_terms, acc_counts} ->
        {acc_terms ++ terms, acc_counts ++ [length(terms)]}
      end)

    # Step 2: Generate embeddings for all terms
    embeddings = embedder.generate(flattened_terms, [])

    # Step 3: Split embeddings back per caller
    embedding_chunks = split_embeddings_by_counts(embeddings, term_counts)

    # Step 4: Send replies
    queue
    |> Enum.zip(embedding_chunks)
    |> Enum.each(fn {{_terms, from}, embeddings_for_request} ->
      GenServer.reply(from, embeddings_for_request)
    end)
  end

  defp flush_batch(_), do: :ok

  defp split_embeddings_by_counts(embeddings, counts) do
    do_split(embeddings, counts, [])
  end

  defp do_split(_remaining, [], acc), do: Enum.reverse(acc)

  defp do_split(remaining, [count | rest], acc) do
    {chunk, rest_embeddings} = Enum.split(remaining, count)
    do_split(rest_embeddings, rest, [chunk | acc])
  end

  defp start_timer(timeout) do
    Process.send_after(self(), :flush, timeout)
  end

  defp cancel_timer(nil), do: :ok
  defp cancel_timer(ref), do: Process.cancel_timer(ref)

  defp embedding_module(opts) do
    Common.get_option!(opts, __MODULE__, :embedding_module)
  end
end
