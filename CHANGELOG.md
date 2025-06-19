# v0.5.2

## New 🔥

- New [demo page](https://torus.dimamik.com) where you can explore different search types and their options. It also includes semantic search, so if you're hesitant - go check it out!
- Other documentation improvements

## Fixes

- Correctly handles `order: :none` in `Torus.semantic/5` search.
- Updates `Torus.Embeddings.HuggingFace` to point to the updated feature extraction endpoint.
- Suppresses warnings for missing `ecto_sql` dependency by adding it to the required dependencies. Most of us already had it, but now it'll be explicit.
- Correctly parses an array of integers in `Torus.QueryInspector.substituted_sql/3` and `Torus.QueryInspector.tap_substituted_sql/3`. Now we should be able to handle all possible query variations.

# v0.5.1

- Adds `Torus.Embeddings.Gemini` to support Gemini embeddings.
- Extends semantic search docs on how to stack embedders
- Adds `:distance_key` option to `Torus.semantic/5` to allow selecting distance key to the result map. Later on we'll rely on this to support hybrid search.
- Correctly swaps `>` and `<` operators for pre-filtering when changing order in `Torus.semantic/5` search.

# v0.5.0

- Similarity search type now defaults to `:word_similarity` instead of `similarity`.
- Possible `Torus.similarity/5` search types are updated to be prefixed with `similarity` to replicate 1-1 these in `pg_trgm` extension.
- Extended optimization section in the docs

# v0.4.1

Minor doc updates

# v0.4.0

## Breaking changes:

- `Torus.full_text/5` - now returns all results when search term contains a stop word or is empty instead of returning none.

## Improvements:

- `Torus.full_text/5` - now supports `:empty_return` option that controls if the query should return all results when search term contains a stop word or is empty.
- `Torus.QueryInspector.tap_explain_analyze/3` - now correctly returns the query plan.
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
