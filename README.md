# Torus

[![CI](https://github.com/dimamik/torus/actions/workflows/ci.yml/badge.svg)](https://github.com/dimamik/torus/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/torus.svg)](https://github.com/dimamik/torus/blob/main/LICENSE)
[![Version](https://img.shields.io/hexpm/v/torus.svg)](https://hex.pm/packages/torus)
[![Hex Docs](https://img.shields.io/badge/documentation-gray.svg)](https://hexdocs.pm/torus)

<!-- MDOC -->

Torus is a plug-and-play Elixir library that seamlessly integrates PostgreSQL's search into Ecto, streamlining the construction of advanced search queries.

## Usage

The package can be installed by adding `torus` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:torus, "~> 0.4"}
  ]
end
```

Then, in any query, you can (for example) add a prefixed full-text search:

```elixir
import Torus
# ...

Post
# ... your complex query
|> Torus.full_text([p], [p.title, p.body], "uncove hogwar")
|> select([p], p.title)
|> Repo.all()
["Uncovered hogwarts"]
```

See `full_text/5` for more details.

## 6 types of search:

1. **Pattern matching**: Searches for a specific pattern in a string.

   ```elixir
   iex> insert_posts!(["Wand", "Magic wand", "Owl"])
   ...> Post
   ...> |> Torus.ilike([p], [p.title], "wan%")
   ...> |> select([p], p.title)
   ...> |> Repo.all()
   ["Wand"]
   ```

   See `like/5`, `ilike/5`, and `similar_to/5` for more details.

1. **Similarity:** Searches for records that closely match the input text, often using trigram or Levenshtein distance. Ideal for fuzzy matching and catching typos in short text fields.

   ```elixir
   iex> insert_posts!(["Hogwarts Secrets", "Quidditch Fever", "Hogwart’s Secret"])
   ...> Post
   ...> |> Torus.similarity([p], [p.title], "hoggwarrds")
   ...> |> limit(2)
   ...> |> select([p], p.title)
   ...> |> Repo.all()
   ["Hogwarts Secrets", "Hogwart’s Secret"]
   ```

   See `similarity/5` for more details.

1. **Text Search Vectors**: Uses term-document matrix vectors for **full-text search**, enabling efficient querying and ranking based on term frequency. - [PostgreSQL: Full Text Search](https://www.postgresql.org/docs/current/textsearch.html). Is great for large datasets to quickly return relevant results.

   ```elixir
   iex> insert_post!(title: "Hogwarts Shocker", body: "A spell disrupts the Quidditch Cup.")
   ...> insert_post!(title: "Diagon Bombshell", body: "Secrets uncovered in the heart of Hogwarts.")
   ...> insert_post!(title: "Completely unrelated", body: "No magic here!")
   ...> Post
   ...> |> Torus.full_text([p], [p.title, p.body], "uncov hogwar")
   ...> |> select([p], p.title)
   ...> |> Repo.all()
   ["Diagon Bombshell"]
   ```

   See `full_text/5` for more details.

1. **Semantic Search**: Understands the contextual meaning of queries to match and retrieve related content utilizing natural language processing. Read more about semantic search in [Semantic search with Torus guide](/guides/semantic_search.md).

   ```elixir
   insert_post!(title: "Hogwarts Shocker", body: "A spell disrupts the Quidditch Cup.")
   insert_post!(title: "Diagon Bombshell", body: "Secrets uncovered in the heart of Hogwarts.")
   insert_post!(title: "Completely unrelated", body: "No magic here!")

   embedding_vector = Torus.to_vector("A magic school in the UK")

   Post
   |> Torus.semantic([p], p.embedding, embedding_vector)
   |> select([p], p.title)
   |> Repo.all()
   ["Diagon Bombshell"]
   ```

   See `semantic/5` for more details.

1. **Hybrid Search**: Combines multiple search techniques (e.g., keyword and semantic) to leverage their strengths for more accurate results.

   Will be added soon.

1. **3rd Party Engines/Providers**: Utilizes external services or software specifically designed for optimized and scalable search capabilities, such as Elasticsearch or Algolia.

## Optimizations and relevance

Torus is designed to be as efficient and relevant as possible from the start. But handling large datasets and complex search queries tends to be tricky. The best way to combine these two to achieve the best result is to:

1. Create a query that returns as relevant results as possible (by tweaking the options of search function). If there is any option missing - feel free to open an issue/contribute back with it, or implement it manually using fragments.
2. Test its performance on real production data - maybe it's good enough already?
3. If it's not:
   - See optimization sections for your search type in `Torus` docs
   - Inspect your query using `Torus.QueryInspector.tap_substituted_sql/3` or `Torus.QueryInspector.tap_explain_analyze/3`
   - According to the above SQL - add indexes for the queried rows/vectors

## Debugging your queries

Torus offers a few helpers to debug, explain, and analyze your queries before using them on production. See `Torus.QueryInspector` for more details.

## Torus support

For now, Torus supports pattern match, similarity, full-text, and semantic search, with plans to expand support further. These docs will be updated with more examples on which search type to choose and how to make them more performant (by adding indexes or using specific functions).

<!-- MDOC -->

## Future plans

- [ ] Add support for highlighting search results. (Base off of a `ts_headline` function)
- [ ] Extend similarity search to support [`fuzzystrmatch`](https://www.postgresql.org/docs/current/fuzzystrmatch.html) extension distance options.
