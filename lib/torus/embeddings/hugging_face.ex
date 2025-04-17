if Code.ensure_loaded?(Req) do
  defmodule Torus.Embeddings.HuggingFace do
    @moduledoc """
    A wrapper around Hugging Face API. It allows you to generate embeddings using a variety of models available on Hugging Face.

    To use it:

    - Add the following to your `config.exs`:

      ```elixir
      config :torus, embedding_module: Torus.Embeddings.HuggingFace
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
      config :torus, Torus.Embeddings.HuggingFace, token: System.get_env("HUGGING_FACE_API_KEY")
      ```

    By default, it uses `sentence-transformers/all-MiniLM-L6-v2` model, but you can specify a different model by explicitly passing `model` to the config:

    ```elixir
    config :torus, Torus.Embeddings.HuggingFace, model: "your/model"
    ```

    See `Torus.semantic/5` on how to use this module to introduce semantic search in your application.
    """
    require Torus
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
