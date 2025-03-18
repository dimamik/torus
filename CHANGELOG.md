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
