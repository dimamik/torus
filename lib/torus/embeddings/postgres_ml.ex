defmodule Torus.Embeddings.PostgresMl do
  @moduledoc """
  Read more about in [PostgresML](https://postgresml.org/blog/semantic-search-in-postgres-in-15-minutes).
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
