# v0.2.2

- `full_text_dynamic/5`: Replaced `:nullable_columns` with `:concat` option
- `similarity/5`: Fixed a bug where you weren't able to pass variable as a term
- `Torus.QueryInspector`: now is not tied with `Torus.Testing` and serves as a separate standalone module.

And other minor performance/clearance improvements.

# v0.2.1

`similarity/5` search is now fully tested and customizable. `full_text_dynamic/5` is up next.

# Changelog for Torus v0.2.0

Torus now supports full text search, ilike, and similarity search.
