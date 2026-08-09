# Hybrid search

This guide walks you through combining several search strategies into a single ranked query with `Torus.hybrid/4`.

## Why hybrid?

Keyword search (`Torus.full_text/5`, `Torus.bm25/5`) is precise: it finds the exact terms the user typed, but misses synonyms and intent. Semantic search (`Torus.semantic/5`) understands meaning, but can miss exact identifiers, names, or rare terms. Hybrid search runs both and fuses the rankings, so documents that both branches like float to the top, while a strong hit in either branch still competes.

Torus fuses branches with [Reciprocal Rank Fusion](https://learn.microsoft.com/en-us/azure/search/hybrid-search-ranking) (RRF). Each branch ranks its top rows, and every row gets a fused score:

```
score = sum over branches of: weight * 1.0 / (k + rank_in_branch)
```

RRF operates on ranks, not raw scores, which sidesteps the problem that `ts_rank_cd`, BM25 scores, and vector distances live on incomparable scales.

## Quick start

```elixir
def search(term) do
  search_vector = Torus.to_vector(term)

  Post
  |> Torus.hybrid([p], [
       full_text: {[p.title, p.body], term},
       semantic: {p.embedding, search_vector, distance: :cosine_distance}
     ],
     limit: 10
   )
  |> Repo.all()
end
```

This runs as **one SQL query**: each branch becomes a ranked subquery keeping its top rows, the ranks are fused with RRF, and the base table is joined back so you get regular `Post` structs in fused order.

Everything piped in **before** `hybrid/4` (filters, joins) applies to every branch. Everything piped **after** composes with the fused result - `select`, `preload`, `where`, pagination. The exceptions: an `order_by` piped in before is discarded (the fused score defines the order), and a `preload` or `offset` piped in before applies only to the fused result, not to the branches.

For generating and storing the embeddings that the `semantic` branch needs, see the [Semantic search guide](semantic_search.md).

## Branches

Branches are a keyword list of `{qualifiers, term}` or `{qualifiers, term, opts}` tuples, mirroring the arguments of the corresponding search macro. Supported types: `:full_text`, `:bm25`, `:similarity`, and `:semantic`. Pattern-match searches (`like`, `ilike`, `similar_to`) have no ranking, so they can't participate.

Each branch accepts its search type's own options (except `:order`), plus:

- `:weight` - multiplier for the branch's contribution (default `1.0`)
- `:limit` - how many top rows the branch contributes (default `20`)

The same type can appear more than once - for example two `semantic` branches over different embedding columns, or two `similarity` branches over different fields:

```elixir
Post
|> Torus.hybrid([p], [
     similarity: {[p.title], term, weight: 2.0},
     similarity: {[p.body], term, weight: 0.5},
     full_text: {[p.title, p.body], term}
   ])
|> Repo.all()
```

## Reading the score

The fused score is exposed through the `:torus_hybrid` named binding:

```elixir
Post
|> Torus.hybrid([p], full_text: {[p.title], term}, semantic: {p.embedding, vector})
|> select([p, torus_hybrid: f], %{title: p.title, score: f.score})
|> Repo.all()
```

Or via the `:score_key` option, if your query already selects a map:

```elixir
Post
|> select([p], %{title: p.title})
|> Torus.hybrid([p], [full_text: {[p.title], term}], score_key: :score)
|> Repo.all()
# => [%{title: "...", score: 0.032}, ...]
```

## Tuning

- **`:k` (default 60)** - the RRF smoothing constant. Higher values flatten the difference between rank 1 and rank 10; lower values make top ranks dominate. 60 comes from the original RRF paper and rarely needs changing.
- **Branch `:weight`** - start with equal weights. If keyword precision matters more (product codes, names), raise the keyword branch; if recall on paraphrased queries matters more, raise the semantic branch.
- **Branch `:limit`** - each branch ranks and contributes at most this many rows. Keep it around 2x your final `:limit` so branches stay cheap top-k queries.

## Performance

Each branch is an independent subquery, so index each one exactly as you would the standalone search:

- `full_text` - GIN index on the tsvector (see `Torus.full_text/5` docs)
- `similarity` - GIN index with `gin_trgm_ops` (see `Torus.similarity/5` docs)
- `semantic` - HNSW or IVFFlat index on the vector column (see `Torus.semantic/5` docs)
- `bm25` - BM25 index (see `Torus.bm25/5` docs)

A branch without a filter ranks every row the base query allows. `similarity` and `semantic` branches don't filter by default - on large tables either pre-filter the base query, use the branch's `pre_filter` option, or make sure the ranking column is indexed so top-k retrieval stays fast.

To inspect the generated SQL, pipe the fused query into `Torus.QueryInspector.tap_substituted_sql/3`.
