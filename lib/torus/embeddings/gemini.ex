if Code.ensure_loaded?(Req) do
  defmodule Torus.Embeddings.Gemini do
    @moduledoc """
    Generates dense vector embeddings through the Gemini API.

    ### How to use

    1. Select the embedding backend

       ```elixir
       # config.exs
       config :torus, embedding_module: Torus.Embeddings.Gemini
       ```

    2. Add `req` to your dependencies

       ```elixir
       def deps do
         [
           {:req, "~> 0.5"}
         ]
       end
       ```

    3. Put your Gemini API token in runtime config

       ```elixir
       # runtime.exs
       config :torus, Torus.Embeddings.Gemini,
         token: System.get_env("GEMINI_API_KEY"),
         # optional – defaults to "text-embedding-004"
         model: "gemini-embedding-exp-03-07"
       ```

    By default, it uses `text-embedding-004` model, but you can specify a different model by explicitly passing `model` to the config:

    ```elixir
    config :torus, Torus.Embeddings.Gemini, model: "your/model"
    ```

    See `Torus.semantic/5` on how to use this module to introduce semantic search in your application.
    """
    require Torus
    alias Torus.Embeddings.Common

    @behaviour Torus.Embedding

    @default_model "text-embedding-004"
    @base_url "https://generativelanguage.googleapis.com/v1beta/models"

    @impl true
    def generate(terms, opts \\ []) when is_list(terms) do
      model = embedding_model(opts)

      token =
        :torus
        |> Application.fetch_env!(__MODULE__)
        |> Keyword.fetch!(:token)

      url = "#{@base_url}/#{model}:batchEmbedContents?key=#{token}"

      body = %{
        "requests" =>
          Enum.map(terms, fn term ->
            %{
              "model" => "models/#{model}",
              "content" => %{"parts" => [%{"text" => term}]},
              "taskType" => "SEMANTIC_SIMILARITY"
            }
          end)
      }

      headers = [{"content-type", "application/json"}]

      Req.post!(url, json: body, headers: headers)
      |> Map.fetch!(:body)
      |> Map.fetch!("embeddings")
      |> Enum.map(fn %{"values" => values} -> Pgvector.new(values) end)
    end

    @impl true
    def embedding_model(opts) do
      Common.get_option(opts, __MODULE__, :model, @default_model)
    end
  end
else
  defmodule Torus.Embeddings.Gemini do
    @moduledoc false
    @behaviour Torus.Embedding

    @impl true
    def generate(_terms, _opts) do
      raise "`Torus.Embeddings.Gemini` is not available – add `req` to your dependencies."
    end

    @impl true
    def embedding_model(_opts),
      do: raise("`Torus.Embeddings.Gemini` is not available – add `req` to your dependencies.")
  end
end
