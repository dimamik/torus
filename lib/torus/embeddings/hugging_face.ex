if Code.ensure_loaded?(Req) do
  defmodule Torus.Embeddings.HuggingFace do
    @moduledoc """
    Embedding generator using Hugging Face Inference API.

    This module requires the `req` library to be added to your dependencies.
    """
    alias Torus.Embeddings.Common

    @behaviour Torus.Embedding
    @default_model "sentence-transformers/all-MiniLM-L6-v2"
    @base_url "https://api-inference.huggingface.co/pipeline/feature-extraction"

    @impl true
    def generate(terms, opts \\ []) when is_list(terms) do
      model = embedding_model(opts)

      token =
        :torus
        |> Application.fetch_env!(__MODULE__)
        |> Keyword.fetch!(:token)

      url = "#{@base_url}/#{model}"

      headers = [
        {"authorization", "Bearer #{token}"},
        {"content-type", "application/json"}
      ]

      [url: url, headers: headers, json: %{"inputs" => terms}]
      |> Req.post!()
      |> Map.fetch!(:body)
      |> Enum.map(&Pgvector.new/1)
    end

    @impl true
    def embedding_model(opts) do
      Common.get_option(opts, __MODULE__, :model, @default_model)
    end
  end
else
  defmodule Torus.Embeddings.HuggingFace do
    @moduledoc false

    @behaviour Torus.Embedding

    @impl true
    def generate(_terms, _opts) do
      raise "`Torus.Embeddings.HuggingFace` is not available. Please add `req` to your dependencies."
    end

    @impl true
    def embedding_model(_opts) do
      raise "`Torus.Embeddings.HuggingFace` is not available. Please add `req` to your dependencies."
    end
  end
end
