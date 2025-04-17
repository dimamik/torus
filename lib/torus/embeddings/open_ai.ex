if Code.ensure_loaded?(Req) do
  defmodule Torus.Embeddings.OpenAI do
    @moduledoc """
    A wrapper around OpenAI API. It allows you to generate embeddings using OpenAI models.

    To use it:

    - Add the following to your `config.exs`:

      ```elixir
      config :torus, embedding_module: Torus.Embeddings.OpenAI
      ```

    - Add `req` to your `mix.exs` dependencies:

      ```elixir
      def deps do
      [
        {:req, "~> 0.5"}
      ]
      end
      ```

    - Add an API token for hugging face to your `runtime.exs`. You can get your token [here](https://huggingface.co/settings/tokens).

      ```elixir
      config :torus, Torus.Embeddings.OpenAI, token: System.get_env("OPEN_AI_API_KEY")
      ```

    By default, it uses `sentence-transformers/all-MiniLM-L6-v2` model, but you can specify a different model by explicitly passing `model` to the config:

    ```elixir
    config :torus, Torus.Embeddings.OpenAI, model: "your/model"
    ```

    See `Torus.semantic/5` on how to use this module to introduce semantic search in your application.
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
