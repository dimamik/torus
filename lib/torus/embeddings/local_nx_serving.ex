if Code.ensure_loaded?(Bumblebee) and Code.ensure_loaded?(Nx) do
  defmodule Torus.Embeddings.LocalNxServing do
    @moduledoc """
    Local embedding generator using local Hugging Face model with Bumblebee and Nx.Serving.

    It allows you to generate embeddings on your local machine using a variety of models available on Hugging Face.

    To use it:

    - Add the following to your `config.exs`:

      ```elixir
      config :torus, embedding_module: Torus.Embeddings.LocalNxServing
      ```

    - Add `bumblebee` and `nx` to your `mix.exs` dependencies:

      ```elixir
      def deps do
      [
        {:bumblebee, "~> 0.6"},
        {:nx, "~> 0.9"}
      ]
      end
      ```

    - Add it to your supervision tree:

    Here you'd probably want to start it only on machines with GPU. See more info in [Nx Serving documentation](https://hexdocs.pm/nx/Nx.Serving.html)

    ```elixir
    def start(_type, _args) do
      children = [
        # Your deps
        Torus.Embeddings.LocalNxServing
      ]

      opts = [strategy: :one_for_one, name: YourApp.Supervisor]
      Supervisor.start_link(children, opts)
    end
    ```

    You can pass all options directly to `Nx.Serving.start_link/1` function by passing them to `Torus.Embeddings.LocalNxServing` when starting.

    By default, it uses `sentence-transformers/all-MiniLM-L6-v2` model, but you can specify a different model by explicitly passing `model` to the config:

    ```elixir
    config :torus, Torus.Embeddings.LocalNxServing, model: "your/model"
    ```

    See `Torus.semantic/5` on how to use this module to introduce semantic search in your application.
    """

    require Logger

    alias Torus.Embeddings.Common

    @behaviour Torus.Embedding
    @default_model "sentence-transformers/paraphrase-MiniLM-L3-v2"

    ## API

    def child_spec(opts) do
      %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}
    end

    def start_link(opts) do
      model_name = embedding_model(opts)

      opts
      |> Keyword.take([:batch_size, :batch_timeout])
      |> Keyword.merge(
        name: __MODULE__,
        serving: build_serving(model_name)
      )
      |> Nx.Serving.start_link()
    end

    @impl true
    def generate(terms, _opts \\ []) do
      __MODULE__
      |> Nx.Serving.batched_run(terms)
      |> Enum.map(&(&1.embedding |> Nx.to_flat_list() |> Pgvector.new()))
    end

    @impl true
    def embedding_model(opts) do
      Common.get_option(opts, __MODULE__, :model, @default_model)
    end

    ## Internal

    defp build_serving(model_name) do
      {:ok, model_info} =
        Bumblebee.load_model({:hf, model_name},
          architecture: :base,
          module: Bumblebee.Text.Bert
        )

      {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, model_name})

      Logger.info("Loaded model #{model_name} via Nx.Serving")

      Bumblebee.Text.text_embedding(model_info, tokenizer, embedding_processor: :l2_norm)
    end
  end
else
  defmodule Torus.Embeddings.LocalNxServing do
    @moduledoc """
    Embedding generator using local Hugging Face model with Bumblebee.
    """

    @behaviour Torus.Embedding

    @error_message """
    `Torus.Embeddings.LocalNxServing` is not available. Please add `:bumblebee` and `:nx` to your dependencies.

    See `Torus.SemanticSearch` docs for more info.
    """

    def child_spec(_opts) do
      raise @error_message
    end

    def start_link(_opts) do
      raise @error_message
    end

    @impl true
    def generate(_terms, _opts) do
      raise @error_message
    end

    @impl true
    def embedding_model(_opts) do
      raise @error_message
    end
  end
end
