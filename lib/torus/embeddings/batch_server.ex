defmodule Torus.Embeddings.BatchServer do
  @moduledoc """
  TODO: Add docs
  A `Torus.Embedding` implementation that batches embedding generation requests together and sends them to `embedding_module` for further processing.

  It will trigger a generation either when a specified number of terms has been queued or when a configurable timeout has been reached.

  ## Features

    * Automatically batches incoming embedding requests.
    * Configurable batch size and timeout (via `:torus` app config or passed options).
    * Forwards batch to the configured embedding adapter module.
    * Splits and replies to individual callers with their respective embeddings.

  ## Configuration

  You can customize the batching behavior using the following application environment keys:

  ```elixir
  config :torus, Torus.Embeddings.BatchServer,
  batch_size: 100,
  batch_timeout: 100
  ```

  These can also be overridden via options passed to start_link/1 or generate/2.

  ## Usage
  Clients should call generate/2 with a list of terms to embed. This call is synchronous and will block until the batch is flushed and embeddings are returned.

  """

  use GenServer
  @behaviour Torus.Embedding

  alias Torus.Embeddings.Common

  @default_batch_size 10
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
       batch_size: Common.get_option(opts, __MODULE__, :batch_size, @default_batch_size),
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

  defp maybe_flush(%{queue: queue, batch_size: batch_size} = state)
       when length(queue) >= batch_size do
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
