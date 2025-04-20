# v0.4.1

Minor doc updates

# v0.4.0

## Breaking changes:

- `full_text/5` - now returns all results when search term contains a stop word or is empty instead of returning none.

## Improvements:

- `full_text/5` - now supports `:empty_return` option that controls if the query should return all results when search term contains a stop word or is empty.
- `tap_explain_analyze/3` - now correctly returns the query plan.
- Docs were grouped together by the search type.

## New 🔥

**Semantic search** is finally here! Read more about it in the [Semantic search with Torus](/guides/semantic_search.md) guide.
  Shortly - it allows you to generate embeddings using a configurable adapters and use them to compare against the ones stored in your database.

Supported adapters (for now):

- `Torus.Embeddings.OpenAI` - uses OpenAI's API to generate embeddings.

- `Torus.Embeddings.HuggingFace` - uses HuggingFace's API to generate embeddings.

- `Torus.Embeddings.LocalNxServing` - generate embeddings on your local machine using a variety of models available on Hugging Face

- `Torus.Embeddings.PostgresML` - uses PostgreSQL [PostgresML extension](https://PostgresML.org/docs) to generate embeddings

- `Torus.Embeddings.Batcher` - a long‑running **GenServer** that collects individual embedding calls, groups them into a single batch, and forwards the batch to the configured `embedding_module` (any from the above or your custom one).

- `Torus.Embeddings.NebulexCache` - a wrapper around [Nebulex](https://hexdocs.pm/nebulex/readme.html) cache, allowing you to cache the embedding calls in memory, so you save the resources/cost of calling the embedding module multiple times for the same input.

And you can easily create your own adapter by implementing the `Torus.Embedding` behaviour.

# v0.3.0

## Breaking changes:

- `full_text_dynamic/5` is renamed to `full_text/5` and now supports stored columns.
- `similarity/5` - `limit` option is removed, use Ecto's `limit/2` instead.
- `full_text/5` - `:concat` option is renamed to `:coalesce`.

## Improvements:

- `full_text/5` now supports stored `tsvector` columns.
- `Torus.QueryInspector.substituted_sql/3` now correctly handles arrays substitutions.
- Docs are extended to guide through the performance and relevance.

And other minor performance/clearance improvements.

# v0.2.2

- `full_text_dynamic/5`: Replaced `:nullable_columns` with `:concat` option
- `similarity/5`: Fixed a bug where you weren't able to pass variable as a term
- `Torus.QueryInspector`: now is not tied with `Torus.Testing` and serves as a separate standalone module.

And other minor performance/clearance improvements.

# v0.2.1

`similarity/5` search is now fully tested and customizable. `full_text_dynamic/5` is up next.

# Changelog for Torus v0.2.0

Torus now supports full text search, ilike, and similarity search.
