if Code.ensure_loaded?(Req) do
  defmodule Torus.Embeddings.OpenAI do
    @moduledoc """
    Embedding generator using OpenAI Embedding API.
    """
    @behaviour Torus.Embedding

    alias Torus.Embeddings.Common

    @default_model "text-embedding-ada-002"
    @base_url "https://api.openai.com/v1/embeddings"

    @impl true
    def generate(terms, opts \\ []) when is_list(terms) do
      model = embedding_model(opts)

      token =
        :torus
        |> Application.fetch_env!(__MODULE__)
        |> Keyword.fetch!(:token)

      headers = [
        {"authorization", "Bearer #{token}"},
        {"content-type", "application/json"}
      ]

      payload = %{
        "input" => terms,
        "model" => model
      }

      [url: @base_url, headers: headers, json: payload]
      |> Req.post!()
      |> Map.fetch!(:body)
      |> Enum.map(& &1["embedding"])
      |> Enum.map(&Pgvector.new/1)
    end

    @impl true
    def embedding_model(opts) do
      Common.get_option(opts, __MODULE__, :model, @default_model)
    end
  end
else
  defmodule Torus.Embeddings.OpenAI do
    @moduledoc """
    Embedding generator using OpenAI Embedding API.
    """

    @behaviour Torus.Embedding

    @impl true
    def generate(_terms, _opts) do
      raise "`Torus.Embeddings.OpenAI` is not available. Please add `req` to your dependencies."
    end

    @impl true
    def embedding_model(_opts) do
      raise "`Torus.Embeddings.OpenAI` is not available. Please add `req` to your dependencies."
    end
  end
end
