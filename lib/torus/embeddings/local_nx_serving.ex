if Code.ensure_loaded?(Bumblebee) and Code.ensure_loaded?(Nx) do
  defmodule Torus.Embeddings.LocalNxServing do
    @moduledoc """
    Local embedding generator using local Hugging Face model with Bumblebee and Nx.Serving.
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

    def embedding_model(opts) do
      raise @error_message
    end
  end
end
