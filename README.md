# Torus

<!-- MDOC -->

Torus is a plug-and-play library that seamlessly integrates PostgreSQL's search into Ecto, streamlining the construction of advanced search queries.

## Usage

The package can be installed by adding `torus` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:torus, "~> 0.2.0"}
  ]
end
```

Then, in any query, you can (for example) add a full-text search:

```elixir
Post
|> Torus.full_text_dynamic([p], [p.title, p.body], "uncovered hogwarts")
|> Repo.all()
```

See `full_text_dynamic/5` for more details.

## 5 types of searches:

1.  **Similarity**: Searches for items that are closely alike based on attributes, often using measures like cosine similarity or Euclidean distance.

    See `similarity/5` for more details.

2.  **Text Search Vectors**: Uses term-document matrix vectors for **full-text search**, enabling
    efficient querying and ranking based on term frequency. - [PostgreSQL: Documentation: 17: Chapter 12. Full Text Search](https://www.postgresql.org/docs/current/textsearch.html)

    ```sql
    SELECT to_tsvector('english', 'The quick brown fox jumps over the lazy dog') @@ to_tsquery('fox & dog');
    ```

    See `full_text_dynamic/5` for more details.

3.  **Semantic Search**: Understands the contextual meaning of queries to match and retrieve related content, often utilizing natural language processing.
    [Semantic Search with PostgreSQL and OpenAI Embeddings | by Dima Timofeev | Towards Data Science](https://towardsdatascience.com/semantic-search-with-postgresql-and-openai-embeddings-4d327236f41f)
4.  **Hybrid Search**: Combines multiple search techniques (e.g., keyword and semantic) to leverage their strengths for more accurate results.
5.  **3rd Party Engines/Providers**: Utilizes external services or software specifically designed for optimized and scalable search capabilities, such as Elasticsearch or Algolia.

## Torus support

For now, Torus supports similarity and full-text search, with plans to expand support further. These docs will be updated with more examples on which search type to choose and how to make them more performant (by adding indexes or using specific functions).

<!-- MDOC -->

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/torus>.
