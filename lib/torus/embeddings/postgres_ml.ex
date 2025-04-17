defmodule Torus.Embeddings.PostgresML do
  @moduledoc """
  `Torus.Embeddings.PostgresML` uses PostgreSQL [PostgresML extension](https://PostgresML.org/docs) to generate embeddings. It allows you to generate embeddings using a variety of models and performs inference directly in the database. This would require your database to have GPU support.

  To use it, add the following to your `config.exs`:

  ```elixir
  config :torus, embedding_module: Torus.Embeddings.PostgresML
  config :torus, Torus.Embeddings.PostgresML, repo: YourApp.Repo
  ```

  By default, it uses `sentence-transformers/all-MiniLM-L6-v2` model, but you can specify a different model by explicitly passing `model` to the config:

  ```elixir
  config :torus, Torus.Embeddings.PostgresML, model: "your/model"
  ```

  Read more about in [PostgresML](https://PostgresML.org/blog/semantic-search-in-postgres-in-15-minutes).

  See `Torus.semantic/5` on how to use this module to introduce semantic search in your application.
  """

  @behaviour Torus.Embedding

  alias Torus.Embeddings.Common

  @default_model "sentence-transformers/paraphrase-MiniLM-L3-v2"

  @impl true
  def generate(terms, opts) do
    model = embedding_model(opts)

    repo =
      Keyword.get(opts, :repo) || Application.get_env(:torus, __MODULE__)[:repo] ||
        raise "#{__MODULE__} requires a `:repo` option"

    "SELECT pgml.embed('#{model}', $1::text[]);"
    |> repo.query!([terms])
    |> Map.fetch!(:rows)
    |> Enum.map(&(&1 |> List.first() |> Pgvector.new()))
  end

  @impl true
  def embedding_model(opts) do
    Common.get_option(opts, __MODULE__, :model, @default_model)
  end
end
