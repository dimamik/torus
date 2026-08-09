defmodule Torus do
  @external_resource readme = Path.join([__DIR__, "../README.md"])

  @moduledoc readme
             |> File.read!()
             |> String.split("<!-- MDOC -->")
             |> Enum.fetch!(1)

  import Ecto.Query, warn: false

  alias Torus.Search.BM25
  alias Torus.Search.FullText
  alias Torus.Search.Highlight
  alias Torus.Search.Hybrid
  alias Torus.Search.PatternMatch
  alias Torus.Search.Semantic
  alias Torus.Search.Similarity

  ## Pattern matching searches

  @doc group: "Pattern matching"
  @doc """
  Case-insensitive pattern matching search using
  [PostgreSQL `ILIKE`](https://www.postgresql.org/docs/current/functions-matching.html#FUNCTIONS-LIKE) operator.

  > #### Warning {: .neutral}
  >
  > Doesn't clean the term, so it needs to be sanitized before being passed in. See
  [LIKE-injections](https://githubengineering.com/like-injection/).
  You can use `Torus.sanitize/1` to clean the term.

  ## Options

    * `:highlight` - a keyword list of result keys to columns to highlight the
    term's matches in, e.g. `highlight: [title: p.title]`. See `highlight/3`.

  ## Examples

      iex> insert_posts!(titles: ["Wand", "Magic wand", "Owl"])
      ...> Post
      ...> |> Torus.ilike([p], [p.title], "wan%")
      ...> |> select([p], p.title)
      ...> |> Repo.all()
      ["Wand"]

      iex> insert_posts!([%{title: "hogwarts", body: nil}, %{title: nil, body: "HOGWARTS"}])
      ...> Post
      ...> |> Torus.ilike([p], [p.title, p.body], "%OGWART%")
      ...> |> select([p], %{title: p.title, body: p.body})
      ...> |> order_by(:id)
      ...> |> Repo.all()
      [%{title: "hogwarts", body: nil}, %{title: nil, body: "HOGWARTS"}]

      iex> insert_post!(title: "MaGiC")
      ...> Post
      ...> |> Torus.ilike([p], p.title, "magi%")
      ...> |> select([p], p.title)
      ...> |> Repo.all()
      ["MaGiC"]

  ## Optimizations

  See `like/5` optimization section for more details.
  """
  defmacro ilike(query, bindings, qualifiers, term, opts \\ []) do
    PatternMatch.ilike(query, bindings, qualifiers, term, opts)
  end

  @doc group: "Pattern matching"
  @doc """
  Case-sensitive pattern matching search using [PostgreSQL `LIKE`](https://www.postgresql.org/docs/current/functions-matching.html#FUNCTIONS-LIKE) operator.

  > #### Warning {: .neutral}
  >
  > Doesn't clean the term, so it needs to be sanitized before being passed in. See
  [LIKE-injections](https://githubengineering.com/like-injection/).
  You can use `Torus.sanitize/1` to clean the term.

  ## Options

    * `:highlight` - a keyword list of result keys to columns to highlight the
    term's matches in, e.g. `highlight: [title: p.title]`. See `highlight/3`.

  ## Examples

      iex> insert_posts!([%{title: "hogwarts", body: nil}, %{title: nil, body: "HOGWARTS"}])
      ...> Post
      ...> |> Torus.like([p], [p.title, p.body], "%OGWART%")
      ...> |> select([p], p.body)
      ...> |> Repo.all()
      ["HOGWARTS"]

  ## Optimizations

  - `like/5` is case-sensitive, so it can take advantage of B-tree indexes when there
  is no wildcard (%) at the beginning of the search term, prefer it over `ilike/5` if
  possible.

    Adding a B-tree index:

      ```sql
      CREATE INDEX index_posts_on_title ON posts (title);
      ```

  - Use `GIN` or `GiST` Index with `pg_trgm` extension for LIKE and ILIKE.

    When searching for substrings (%word%), B-tree indexes won't help. Instead,
    use trigram indexing (`pg_trgm` extension):

      ```sql
      CREATE EXTENSION IF NOT EXISTS pg_trgm;
      CREATE INDEX posts_title_trgm_idx ON posts USING GIN (title gin_trgm_ops);
      ```

  - If using prefix search, convert data to lowercase and use B-tree index for
    case-insensitive search:

      ```sql
      ALTER TABLE posts ADD COLUMN title_lower TEXT GENERATED ALWAYS AS (LOWER(title)) STORED;
      CREATE INDEX index_posts_on_title ON posts (title_lower);
      ```

      ```elixir
      Torus.like([p], [p.title_lower], "hogwarts%")
      ```

  - Use full-text search for large text fields, see `full_text/5` for more
  details.
  """
  defmacro like(query, bindings, qualifiers, term, opts \\ []) do
    PatternMatch.like(query, bindings, qualifiers, term, opts)
  end

  @doc group: "Pattern matching"
  @doc """
  Similar to `like/5`, except that it interprets the pattern using the SQL standard's
  definition of a regular expression. SQL regular expressions are a curious cross between
  LIKE notation and common (POSIX) regular expression notation. See
  [PostgreSQL `SIMILAR TO`](https://postgresql.org/docs/current/interactive/functions-matching.html?fts_query=ilike#FUNCTIONS-SIMILARTO-REGEXP)

  ## Examples

      iex> insert_post!(body: "abc")
      ...> Post
      ...> |> Torus.similar_to([p], [p.title, p.body], "%(b|d)%")
      ...> |> select([p], p.body)
      ...> |> Repo.all()
      ["abc"]

  ## Optimizations
  - If regex is needed, use POSIX regex with `~` or `~*` operators since they _may_
  leverage GIN or GiST indexes in some cases. These operators will be introduced later on.
  - Use `ilike/5` or `like/5` when possible, `similar_to/5` almost always does full table scans
  - Filter and limit the result set as much as possible before calling `similar_to/5`
  """
  # TODO: Adjust the description when POSIX regex is added
  defmacro similar_to(query, bindings, qualifiers, term, _opts \\ []) do
    PatternMatch.similar_to(query, bindings, qualifiers, term)
  end

  @doc group: "Pattern matching"
  @doc """
  Removes all like/ilike special characters from the term, so it can be used in further pattern-match searches.

  ## Examples

      iex> Torus.sanitize(~S"%_\\realterm%")
      "realterm"
  """
  def sanitize(term) do
    PatternMatch.sanitize(term)
  end

  # -----------------------------------
  # TODO: Add POSIX Regular Expressions
  # -----------------------------------

  @doc group: "Similarity"
  @doc """
  Searches for records that closely match the input text using trigram distance. Ideal for fuzzy matching and catching typos in short text fields.

  Implemented using case-insensitive similarity search using [PostgreSQL similarity functions](https://postgresql.org/docs/current/interactive/pgtrgm.html#PGTRGM-FUNCS-OPS).

  > #### Warning {: .neutral}
  >
  > You need to have `pg_trgm` extension installed.
  > ```elixir
  > defmodule YourApp.Repo.Migrations.CreatePgTrgmExtension do
  >   use Ecto.Migration
  >
  >   def change do
  >     execute "CREATE EXTENSION IF NOT EXISTS pg_trgm", "DROP EXTENSION IF EXISTS pg_trgm"
  >   end
  > end
  > ```

  ## Options

    * `:type` - similarity type. Possible options are:
      - `:word_similarity` (default) - uses `pg_trgm` `word_similarity` function. Use
      it if you're dealing with sentences and you don't want the length of the
      strings to affect the search result.
      - `:strict_word_similarity` - uses `strict_word_similarity` function.
      Prioritizes full matches, forces extent boundaries to match word boundaries.
      Since we don't have cross-word trigrams, this function actually returns
      greatest similarity between first string and any continuous extent of words of
      the second string.
      - `:similarity` - uses `similarity` function. Compares the whole set of trigrams
      instead of an ordered subset. Use this when you search for the exact phrase or a string,
      not a word/phrase in a sentence/longer text.
    * `:order` - describes the ordering of the results. Possible values are
      - `:desc` (default) - orders the results by similarity rank in descending order.
      - `:asc` - orders the results by similarity rank in ascending order.
      - `:none` - doesn't apply ordering and returns
    * `:pre_filter` - whether or not to pre-filter the results:
      - `false` (default) - omits pre-filtering and returns all results.
      - `true` -  before applying the order, pre filters (using boolean
    operators which potentially use GIN indexes) the result set. The results above
    `pg_trgm.{type}_threshold` are returned. It is advised to set the corresponding value to `0.3` so that more relevant results are returned.
    For example, for `word_similarity`, we'd run `SET pg_trgm.word_similarity_threshold = 0.3;`.
    * `:highlight` - a keyword list of result keys to columns to highlight the
    term's exact-word matches in, e.g. `highlight: [title: p.title]`. See `highlight/3`.

  ## Examples

      iex> insert_post!(title: "Hogwarts Shocker", body: "A spell disrupts the Quidditch Cup.")
      ...> insert_post!(title: "Diagon Bombshell", body: "Secrets uncovered in the heart of Hogwarts.")
      ...> insert_post!(title: "Completely unrelated", body: "No magic here!")
      ...>  Post
      ...> |> Torus.similarity([p], [p.title, p.body], "Diagon Bombshell")
      ...> |> limit(1)
      ...> |> select([p], p.title)
      ...> |> Repo.all()
      ["Diagon Bombshell"]

      iex> insert_posts!(["Wand", "Owl", "What an amazing cloak"])
      ...> Post
      ...> |> Torus.similarity([p], [p.title], "owls", pre_filter: true)
      ...> |> select([p], p.title)
      ...> |> Repo.all()
      ["Owl"]

  ## Optimizations

  - Use `pre_filter: true` to pre-filter the results before applying the order.
  This would significantly reduce the number of rows to order. The pre-filtering
  phase uses different (boolean) similarity operators which more actively leverage
  GIN indexes.
  - Use `order: :none` argument if you don't care about the order of the results.
  The query will return all results that are above the similarity threshold, which
  you can set globally via `SET pg_trgm.{type}_threshold = 0.3;`, replacing type
  with your `type` option (e.g. `word_similarity_threshold`).
  - When `order: :desc` (default) and the limit is not set, the query will do a full
  table scan, so it's recommended to manually limit the results (by applying `where`
  or `limit` clauses to filter the rows as much as possible).

  ### Adding an index

  ```sql
  -- If you haven't created it yet
  CREATE EXTENSION IF NOT EXISTS pg_trgm;

  CREATE INDEX index_posts_on_title ON posts USING GIN (title gin_trgm_ops);
  ```
  """
  defmacro similarity(query, bindings, qualifiers, term, opts \\ []) do
    Similarity.similarity(query, bindings, qualifiers, term, opts)
  end

  # ----------------------------------------------------------------
  # TODO: Combine different types of searches (or at least show how)
  # ----------------------------------------------------------------

  @doc group: "Full text"
  @doc """
  Full text search with rank ordering. Accepts a list of columns to search in. A list of columns
  can either be a text or `tsvector` type. If `tsvector`s are passed make sure to set
  `stored: true`.

  Cleans the term, so it can be input directly by the user. The default preset of
  settings is optimal for most cases.

  Full Text Searching (or just text search) provides the capability to identify
  natural-language documents that satisfy a query, and optionally to sort them by
  relevance to the query. The most common type of search is to find all documents
  containing given query terms and return them in order of their similarity to the query.
  Notions of query and similarity are very flexible and depend on the specific application.
  The simplest search considers query as a set of words and similarity as the frequency of
  query words in the document. Read more in [PostgreSQL Full Text Search docs](https://postgresql.org/docs/current/interactive/textsearch-intro.html).

  ## Options
    * `:prefix_search` - whether to apply prefix search.
      - `true` (default) - the term is treated as a prefix
      - `false` - only counts full-word matches
    * `:stored` - whether to use stored tsvector or not.
      - `false` (default) - columns (or expressions) passed as qualifiers are of type `text`
      - `true` - columns (or expressions) passed as qualifiers are **tsvectors**
    * `:language` - language used for the search. Defaults to `"english"`.
    * `:term_function` - function used to convert the term to `ts_query`. Can be one of:
      - `:websearch_to_tsquery` (default) - converts term to a tsquery, normalizing
      words according to the specified or default configuration. Quoted word sequences
      are converted to phrase tests. The word “or” is understood as producing an OR
      operator, and a dash produces a NOT operator; other punctuation is ignored. This
      approximates the behavior of some common web search tools.
      - `:plainto_tsquery` - converts term to a tsquery, normalizing words according
      to the specified or default configuration. Any punctuation in the string is
      ignored (it does not determine query operators). The resulting query matches
      documents containing all non-stopwords in the term.
      - `:phraseto_tsquery` - converts term to a tsquery, normalizing words according
      to the specified or default configuration. Any punctuation in the string is
      ignored (it does not determine query operators). The resulting query matches
      phrases containing all non-stopwords in the text.
    * `:rank_function` - function used to rank the results.
      - `:ts_rank_cd` (default) - computes a score showing how well the vector matches
      the query, using a cover density algorithm. See [Ranking Search Results](https://postgresql.org/docs/current/interactive/textsearch-controls.html#TEXTSEARCH-RANKING) for more details.
      - `:ts_rank` - computes a score showing how well the vector matches the query.
    * `:rank_weights` - a list of weights for each column. Defaults to `[:A, :B, :C, :D]`.
    The length of weights (if provided) should be the same as the length of the columns we search for.
    A single weight can be either a string or an atom. Possible values are:
      - `:A` - 1.0
      - `:B` - 0.4
      - `:C` - 0.2
      - `:D` - 0.1
    * `:rank_normalization` - a string that specifies whether and how a document's
    length should impact its rank. The integer option controls several behaviors, so
    it is a bit mask: you can specify one or more behaviors using `|` (for example, `2|4`).
      - `0` (default for `ts_rank`) - ignores the document length
      - `1`  - divides the rank by 1 + the logarithm of the document length
      - `2`  - divides the rank by the document length
      - `4` (default for `ts_rank_cd`)  - divides the rank by the mean harmonic
      distance between extents (this is implemented only by `ts_rank_cd`)
      - `8`  - divides the rank by the number of unique words in document
      - `16` -  divides the rank by 1 + the logarithm of the number of unique words in
      document
      - `32` - divides the rank by itself + 1
    * `:order` - describes the ordering of the results. Possible values are
      - `:desc` (default) - orders the results by similarity rank in descending order.
      - `:asc` - orders the results by similarity rank in ascending order.
      - `:none` - doesn't apply ordering at all.
    * `:filter_type` - filter type
      - `:or` (default) - uses `OR` operator to combine different column matches.
      Selecting this option means that the search term won't match across columns.
      - `:concat` - joins the columns into a single tsvector and searches for the
      term in the concatenated string containing all columns.
      - `:none` - doesn't apply any filtering and returns all results.
    * `empty_return` - whether to return all results when the search term is empty.
      - `true` (default) - returns all results when the search term is empty.
      - `false` - returns an empty list when the search term is empty.
    * `:highlight` - a keyword list of result keys to columns to highlight the
    term's matches in, e.g. `highlight: [title: p.title]`. See `highlight/3`.
    * `:coalesce` - when joining columns via `:concat` option, adds a
    `COALESCE` function to handle NULL values. Choose true when you can't guarantee
    that all columns are non-null.
      - `true` (default)- adds `COALESCE`
      - `false` - doesn't add `COALESCE` function to the query. Choose this when you're
      using `filter_type: :concat` and can guarantee that all columns are non-null.

  ## Example usage

      iex> insert_post!(title: "Hogwarts Shocker", body: "A spell disrupts the Quidditch Cup.")
      ...> insert_post!(title: "Diagon Bombshell", body: "Secrets uncovered in the heart of Hogwarts.")
      ...> insert_post!(title: "Completely unrelated", body: "No magic here!")
      ...>  Post
      ...> |> Torus.full_text([p], [p.title, p.body], "uncov hogwar")
      ...> |> select([p], p.title)
      ...> |> Repo.all()
      ["Diagon Bombshell"]

  ## Optimizations

    - Store precomputed tsvector in a separate column, add a GIN index to it, and use
    `stored: true`.

    - Add a GIN tsvector index on the column(s) you search in.
    Use `Torus.QueryInspector.tap_sql/2` on your query (with all the options passed) to see the exact search string and add an index to it. For example for nullable title, the GIN index could look like:

      ```sql
      CREATE INDEX index_gin_posts_title
      ON posts USING GIN (to_tsvector('english', COALESCE(title, '')));
      ```
  """
  defmacro full_text(query, bindings, qualifiers, term, opts \\ []) do
    FullText.full_text(query, bindings, qualifiers, term, opts)
  end

  @doc false
  defmacro to_tsquery(column, query_text, opts \\ []) do
    FullText.to_tsquery(column, query_text, opts)
  end

  @doc group: "Full text"
  @doc """
  Highlights matches of `term` in `qualifier` using PostgreSQL
  [`ts_headline`](https://postgresql.org/docs/current/interactive/textsearch-controls.html#TEXTSEARCH-HEADLINE).

  Use it in `select`/`select_merge` alongside any search macro. Two highlighting
  types are supported via the `:type` option:

    * `:word` (default) - word-based, uses the same term parsing as `full_text/5`,
    so it pairs naturally with `full_text/5`, `bm25/5`, and `hybrid/4`. It also
    highlights the exact-word matches of `similarity/5` (though not its fuzzy
    matches).
    * `:substring` - highlights every occurrence of the term as a plain substring
    (implemented with `regexp_replace`, the term is regex-escaped). Pairs with
    `ilike/5` and `like/5`, whose `%term%` patterns match inside words where
    word-based highlighting finds nothing.

  `semantic/5` matches aren't lexical, so there is nothing to highlight there.

  ## Highlighting from the search macros

  Instead of repeating the term, pass `highlight: [result_key: column]` directly to
  `full_text/5`, `bm25/5`, `similarity/5`, `ilike/5`, `like/5`, or a `hybrid/4`
  branch's options - the search's own term and options are reused. `ilike/5`/`like/5` highlight as substrings with the
  macro's case sensitivity, stripping `%`/`_` wildcards from the term; the rest
  highlight word matches. The highlighted value is merged via `select_merge/3`, so
  either use a key that exists on the selected struct (its value is replaced with
  the highlighted text) or select a map before the search macro.

      iex> insert_post!(title: "Hogwarts Shocker")
      ...> Post
      ...> |> Torus.full_text([p], [p.title], "shocker", highlight: [title: p.title])
      ...> |> Repo.all()
      ...> |> Enum.map(& &1.title)
      ["Hogwarts <b>Shocker</b>"]

      iex> insert_post!(title: "Hogwarts Shocker")
      ...> Post
      ...> |> Torus.ilike([p], [p.title], "%ogwart%", highlight: [title: p.title])
      ...> |> Repo.all()
      ...> |> Enum.map(& &1.title)
      ["H<b>ogwart</b>s Shocker"]

  > #### Warning {: .neutral}
  >
  > The returned text is **not** HTML-escaped - the column content is returned
  > as-is with the matches wrapped in `:start_sel`/`:stop_sel`. If you render it as
  > raw HTML, either sanitize the result or use unique markers (e.g.
  > `start_sel: "@@", stop_sel: "@@"`), escape the result, and only then convert
  > the markers to tags.

  ## Options

    * `:type` - `:word` (default) or `:substring`, see above.
    * `:start_sel`, `:stop_sel` - strings the matches are wrapped in. Default to
    `"<b>"` and `"</b>"`.

  Options for `type: :substring`:

    * `:case_sensitive` - defaults to `false` (matching `ilike/5`); set to `true`
    to only highlight exact-case occurrences (matching `like/5`).

  Options for `type: :word`:

    * `:language` - language used for the search. Defaults to `"english"`.
    * `:term_function` - function used to convert the term to `ts_query`. Same
    options as in `full_text/5`. Defaults to `:websearch_to_tsquery`.
    * `:prefix_search` - whether to also highlight words the term matches as a
    prefix. Defaults to `true` (same as `full_text/5`).
    * `:highlight_all` - whether to return the whole document.
      - `true` (default) - returns the full text with all matches highlighted.
      - `false` - returns a fragment (snippet) around the matches, controlled by
      the options below.
    * `:max_words`, `:min_words` - fragment size when `highlight_all: false`.
    Default to PostgreSQL's `35` and `15`.
    * `:short_word` - words of this length or less are dropped at fragment
    start/end. Defaults to `3`.
    * `:max_fragments` - maximum number of fragments to return. Defaults to `0`.
    * `:fragment_delimiter` - string used to join fragments. Defaults to `" ... "`.

  ## Examples

      iex> insert_post!(title: "Hogwarts Shocker", body: "A spell disrupts the Quidditch Cup.")
      ...> Post
      ...> |> Torus.full_text([p], [p.title, p.body], "shocker")
      ...> |> select([p], Torus.highlight(p.title, "shocker"))
      ...> |> Repo.all()
      ["Hogwarts <b>Shocker</b>"]

  With a snippet instead of the full text:

      iex> insert_post!(body: "A magic spell disrupts the Quidditch Cup final at Hogwarts.")
      ...> Post
      ...> |> Torus.full_text([p], [p.body], "quidditch")
      ...> |> select([p], Torus.highlight(p.body, "quidditch", highlight_all: false, max_words: 5, min_words: 2))
      ...> |> Repo.all()
      ["<b>Quidditch</b> Cup final"]

  Substring highlighting alongside `ilike/5`:

      iex> insert_post!(title: "Hogwarts Shocker")
      ...> Post
      ...> |> Torus.ilike([p], [p.title], "%ogwart%")
      ...> |> select([p], Torus.highlight(p.title, "ogwart", type: :substring))
      ...> |> Repo.all()
      ["H<b>ogwart</b>s Shocker"]
  """
  defmacro highlight(qualifier, term, opts \\ []) do
    Highlight.highlight(qualifier, term, opts)
  end

  @doc group: "Full text"
  @doc """
  BM25 ranked full-text search using the [pg_textsearch](https://github.com/timescale/pg_textsearch) extension.

  BM25 is a modern ranking function that generally provides better relevance than traditional
  TF-IDF (used by `full_text/5`). It's particularly effective for top-k queries with LIMIT clauses
  due to Block-Max WAND optimization.

  For detailed usage examples, performance tips, and migration guide, see the [BM25 Search guide](https://dimamik.com/posts/bm25_search).

  > #### Requirements {: .warning}
  >
  > - Requires the `pg_textsearch` extension to be installed
  > - PostgreSQL 17+ only
  > - Requires a BM25 index on the search column
  > - **Single column only** - unlike `full_text/5`, BM25 indexes work on one column at a time
  > - **Language is set at index creation** - use `text_config` in the index `WITH` clause
  >
  > ```elixir
  > defmodule YourApp.Repo.Migrations.CreatePgTextsearchExtension do
  >   use Ecto.Migration
  >
  >   def change do
  >     execute "CREATE EXTENSION IF NOT EXISTS pg_textsearch", "DROP EXTENSION IF EXISTS pg_textsearch"
  >
  >     # Create BM25 index with language configuration
  >     execute \"\"\"
  >     CREATE INDEX posts_body_bm25_idx ON posts
  >     USING bm25(body) WITH (text_config='english')
  >     \"\"\", "DROP INDEX posts_body_bm25_idx"
  >   end
  > end
  > ```

  ## Options

    * `:order` - Ordering of results. Note that BM25 returns **negative scores** (lower is better):
      - `:asc` (default) - orders by score ascending (best matches first)
      - `:desc` - orders by score descending (worst matches first)
      - `:none` - no ordering applied
    * `:index_name` - Explicit index name. Required when using `score_threshold`.
    * `:score_key` - Atom key to select the BM25 score into the result map. The score
    is merged via `select_merge/3`, so the query needs to select a map **before**
    calling `bm25/5` (e.g. `select([p], %{body: p.body})`).
      - `:none` (default) - score is not selected
      - `atom` - selects score as this key
    * `:score_threshold` - Post-filter results by BM25 score (applied after ORDER BY).
      Since scores are negative and lower is better, use negative thresholds (e.g., `-3.0`
      keeps only results with score < -3.0, i.e., scores like -4.0, -5.0 which are better matches).
      May return fewer results than LIMIT.
    * `:pre_filter` - Whether to exclude non-matching rows.
      - `false` (default) - no pre-filtering
      - `true` - adds a `WHERE score < 0` clause to exclude non-matches
    * `:highlight` - a keyword list of result keys to columns to highlight the
    term's matches in, e.g. `highlight: [body: p.body]`. See `highlight/3`.

  ## Examples

  Basic search - returns top 10 most relevant posts:

      Post
      |> Torus.bm25([p], p.body, "database search")
      |> limit(10)
      |> select([p], p.body)
      |> Repo.all()

  With score selection (select a map before calling, so the score has somewhere to merge into):

      Post
      |> select([p], %{body: p.body})
      |> Torus.bm25([p], p.body, "database", score_key: :relevance)
      |> limit(5)
      |> Repo.all()
      # => [%{body: "...", relevance: -2.5}, ...]

  With WHERE clause pre-filtering:

      Post
      |> where([p], p.category_id == 123)
      |> Torus.bm25([p], p.body, "database")
      |> limit(10)
      |> Repo.all()

  With score threshold (post-filtering, may return fewer than LIMIT, `index_name` is required):

      Post
      |> Torus.bm25([p], p.body, "database", score_threshold: -5.0, index_name: "posts_body_idx")
      |> limit(10)
      |> Repo.all()

  ## When to use `bm25/5` vs `full_text/5`

  **Use `bm25/5` when:**
  - You need better relevance ranking than TF-IDF
  - You need faster search with large datasets
  - You have large result sets with LIMIT (top-k queries)
  - Single column search is sufficient
  - You're on PostgreSQL 17+

  **Use `full_text/5` when:**
  - You need multi-column search with different weights per column
  - You want to use stored tsvector columns
  - You're on PostgreSQL < 17
  - You need the `concat` filter type

  ## Index options

  BM25 indexes support these parameters in the `WITH` clause:

  - `text_config` - PostgreSQL text search configuration (required). This determines
    the language/stemming rules. Available configs: `'english'`, `'french'`, `'german'`,
    `'simple'` (no stemming), etc. Run `SELECT cfgname FROM pg_ts_config;` to list all.
  - `k1` - Term frequency saturation (default: 1.2, range: 0.1-10.0)
  - `b` - Length normalization (default: 0.75, range: 0.0-1.0)

  ```sql
  CREATE INDEX custom_idx ON documents
  USING bm25(content)
  WITH (text_config='english', k1=1.5, b=0.8);
  ```

  ## Performance tips

  - BM25 is most efficient with `ORDER BY + LIMIT` (enables Block-Max WAND optimization)
  - For filtered searches, create a separate B-tree index on the filter column
  - Pre-filtering works best when the filter is selective (<10% of rows)
  - Post-filtering with `score_threshold` may return fewer results than LIMIT
  """
  defmacro bm25(query, bindings, qualifier, term, opts \\ []) do
    BM25.bm25(query, bindings, qualifier, term, opts)
  end

  @doc group: "Hybrid"
  @doc """
  Hybrid search: fuses several search strategies into a single ranked query using
  [Reciprocal Rank Fusion](https://learn.microsoft.com/en-us/azure/search/hybrid-search-ranking)
  (RRF). Each branch runs as an independent ranked subquery, keeps its `limit` best rows,
  and the results are merged by summing `weight * 1.0 / (k + rank)` per row across branches.

  Rows that rank high in several branches win; rows found by only one branch still
  compete. This is the standard way to combine keyword (`full_text/5`, `bm25/5`) and
  semantic (`semantic/5`) search, and generally outperforms each on its own.

  ## Search branches

  The third argument is a keyword list of search branches. Keys are search types -
  `:full_text`, `:similarity`, `:semantic`, or `:bm25` (pattern-match searches have no
  ranking, so they can't participate). The same type can appear more than once. Values
  are `{qualifiers, term}` or `{qualifiers, term, opts}` tuples mirroring the
  corresponding search macro's arguments.

  Branch `opts` accept the search type's own options (except `:order`, `:score_key`,
  and `:distance_key` - branches are always ranked best-first, and the fused score is
  exposed by `hybrid/4` itself), plus:

    * `:weight` - multiplier for this branch's RRF score. Defaults to `1.0`.
    * `:limit` - how many top rows this branch contributes. Defaults to `20`.
    * `:highlight` - a keyword list of result keys to columns to highlight this
    branch's term matches in, e.g. `highlight: [title: p.title]`. Not supported in
    `:semantic` branches. See `highlight/3`.

  In `full_text` branches `empty_return` defaults to `false`, so an empty search term
  contributes no rows to the fusion instead of boosting arbitrary ones.

  ## Options

    * `:k` - RRF smoothing constant. Higher values flatten the difference between
    ranks. Defaults to `60`.
    * `:limit` - final limit applied to the fused result.
    * `:score_key` - atom key to select the fused score into the result map. The score
    is merged via `select_merge/3`, so the query needs to select a map **before**
    calling `hybrid/4`. The score is also available directly through the
    `:torus_hybrid` named binding.
    * `:primary_key` - column used to match rows across branches. Defaults to the
    schema's primary key.

  ## Examples

      iex> insert_post!(title: "Hogwarts Shocker", body: "A spell disrupts the Quidditch Cup.")
      ...> insert_post!(title: "Diagon Bombshell", body: "Secrets uncovered in the heart of Hogwarts.")
      ...> insert_post!(title: "Completely unrelated", body: "No magic here!")
      ...> Post
      ...> |> Torus.hybrid([p], [
      ...>      full_text: {[p.title, p.body], "uncov hogwar"},
      ...>      similarity: {[p.title], "hogwarts"}
      ...>    ])
      ...> |> select([p], p.title)
      ...> |> Repo.all()
      ["Diagon Bombshell", "Hogwarts Shocker", "Completely unrelated"]

  With semantic search, weights, and the fused score selected:

      search_vector = Torus.to_vector("A magic school in the UK")

      Post
      |> select([p], %{title: p.title})
      |> Torus.hybrid([p], [
           full_text: {[p.title, p.body], "magic school", weight: 1.0},
           semantic: {p.embedding, search_vector, distance: :cosine_distance, weight: 2.0}
         ],
         limit: 10,
         score_key: :score
       )
      |> Repo.all()
      # => [%{title: "...", score: 0.047}, ...]

  The fused query is a regular Ecto query - you can keep piping `select`, `preload`,
  `where`, or pagination onto it. The base query's filters (everything piped in before
  `hybrid/4`) apply to every branch. An `order_by` piped in before `hybrid/4` is
  discarded - the fused score defines the order - and a `preload` or `offset` piped in
  before applies only to the fused result, not to the branches.

  ## Optimizations

  - Each branch is a separate subquery, so index each branch's search the same way
  you would index the standalone search macro (GIN for full text and trigrams, HNSW /
  IVFFlat for vectors, BM25 index for `bm25/5`).
  - Branch `:limit` caps how many rows each branch ranks and contributes - keep it
  close to your final `:limit` (2x is a good default) so branches stay top-k friendly.
  - A branch without a filter (for example `similarity` without `pre_filter: true`, or
  `full_text` with `filter_type: :none`) ranks every row the base query allows, which
  is a full scan without a matching index. Prefer filtered branches on large tables.
  - `:k` rarely needs tuning - 60 is the standard from the RRF paper and works well.
  """
  defmacro hybrid(query, bindings, searches, opts \\ []) do
    Hybrid.hybrid(query, bindings, searches, opts)
  end

  @doc group: "Pattern matching"
  @doc """
  The substring function with three parameters provides extraction of a substring
  that matches an SQL regular expression pattern. The function can be written
  according to standard SQL syntax:

  ```sql
  substring('foobar' similar '%#"o_b#"%' escape '#')   oob
  substring('foobar' similar '#"o_b#"%' escape '#')    NULL
  ```

  ## Examples

  ```elixir
  insert_post!(title: "Hello123World")
  Post |> select([p], substring(p.title, "[0-9]+", "#")) |> Repo.all()
  ["123"]
  ```
  """
  defmacro substring(string, pattern, escape_character) do
    quote do
      fragment(
        "substring(? similar ? escape ?)",
        unquote(string),
        ^unquote(pattern),
        ^unquote(escape_character)
      )
    end
  end

  # Private macros

  @doc false
  defmacro operator(a, operator, b) do
    quote do
      fragment(unquote("? #{operator} ?"), unquote(a), unquote(b))
    end
  end

  @doc false
  defmacro concat_ws(separator \\ " ", qualifiers) do
    fragment_string = "concat_ws(?" <> String.duplicate(", ?", length(qualifiers)) <> ")"

    quote do
      fragment(
        unquote(fragment_string),
        unquote(separator),
        unquote_splicing(qualifiers)
      )
    end
  end

  @doc group: "Semantic"
  @doc """
  Semantic search using pgvector extension to compare vectors. See [Semantic search guide](semantic_search.html) for more info.

  ## Options
    * `:distance` - a way to calculate the distance between the vectors. Can be one of:
      - `:l2_distance` (default) - L2 distance
      - `:max_inner_product` - negative inner product
      - `:cosine_distance` - cosine distance
      - `:l1_distance` - L1 distance
      - `:hamming_distance` - (binary vectors only) Hamming distance
      - `:jaccard_distance` - (binary vectors only) Jaccard distance
    * `:order` - describes the ordering of the results. Possible values are
      - `:asc` (default) - orders the results by distance in ascending order. 0 distance means that the vectors are the same meaning the the terms are equal. The closer the vectors - more aligned are the terms.
      - `:desc` - orders the results by distance in descending order.
      - `:none` - doesn't apply ordering at all.
    * `:pre_filter` - a positive float that is passed directly to the query to pre-filter the results.
      - `:none` (default) - no pre-filtering is done.
      - `float` - pre-filters the results before applying the order. The results with vectors distance below the pre-filter value are returned.
    * `:distance_key` - pass an atom to put the selected distance under in the result
    map. The distance is merged via `select_merge/3`, so the query needs to select a
    map **before** calling `semantic/5` (e.g. `select([p], %{title: p.title})`).
      - `:none` (default) - the distance is not selected.
      - `atom` - the map key the distance is put under.

  ## Examples

      def search(term) do
        search_vector = Torus.to_vector(term)

        Post
        |> Torus.semantic([p], p.embedding, search_vector)
        |> Repo.all()
      end

  ## Optimizations
  - Use `pre_filter` to pre-filter the results before applying the order. This would significantly reduce the number of rows to order.
  - Index embeddings column:

      - HNSW (Hierarchical Navigable Small World) - High-accuracy Approximate Nearest
      Neighbor
        ```sql
        CREATE INDEX ON embeddings USING hnsw (embedding vector_l2_ops) WITH (m = 16, ef_construction = 200);
        ```

      - IVFFlat Index (Approximate Nearest Neighbor) with different similarity
      functions. Prior to index creation, it's recommended to have some real data in place, so the quality of clusters is better.
        - Cosine Similarity
          ```sql
          CREATE INDEX ON embeddings USING ivfflat (embedding vector_cosine_ops);
          ```
        - L2 Distance
          ```sql
          CREATE INDEX ON embeddings USING ivfflat (embedding vector_l2_ops);
          ```
        - Inner Product
          ```sql
          CREATE INDEX ON embeddings USING ivfflat (embedding vector_ip_ops);
          ```
  """
  defmacro semantic(query, bindings, qualifier, vector_term, opts \\ []) do
    Semantic.semantic(query, bindings, qualifier, vector_term, opts)
  end

  @doc group: "Semantic"
  @doc """
  Takes a list of terms (binaries) and embedding module's specific options and passes them to `embedding_module` `generate/2` function.

  Configure `embedding_module` either in `config.exs`:

        config :torus, :embedding_module, Torus.Embeddings.HuggingFace

  or pass `embedding_module` as an option to `to_vectors/2` function. Options always
  have greater priority than the config.

  See [Semantic search guide](semantic_search.html) for more info.
  """
  defdelegate to_vectors(terms, opts \\ []), to: Semantic

  @doc group: "Semantic"
  @doc """
  Same as `to_vectors/2`, but returns the first vector from the list.
  """
  defdelegate to_vector(term, opts \\ []), to: Semantic

  @doc group: "Semantic"
  @doc """
  Calls the specified embedding module's `embedding_model/1` function to retrieve the model name.

  See [Semantic search guide](semantic_search.html) for more info.
  """
  defdelegate embedding_model(opts \\ []), to: Semantic
end
