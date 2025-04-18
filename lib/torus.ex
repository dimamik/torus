defmodule Torus do
  @external_resource readme = Path.join([__DIR__, "../README.md"])

  @moduledoc readme
             |> File.read!()
             |> String.split("<!-- MDOC -->")
             |> Enum.fetch!(1)

  import Ecto.Query, warn: false

  ## Pattern matching searches

  @doc group: "Pattern matching"
  @doc """
  Case-insensitive pattern matching search using
  [PostgreSQL `ILIKE`](https://www.postgresql.org/docs/current/functions-matching.html#FUNCTIONS-LIKE) operator.

  > #### Warning {: .neutral}
  >
  > Doesn't clean the term, so it needs to be sanitized before being passed in. See
  [LIKE-injections](https://githubengineering.com/like-injection/).

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
  defmacro ilike(query, bindings, qualifiers, term, _opts \\ []) do
    Torus.Search.PatternMatch.ilike(query, bindings, qualifiers, term)
  end

  @doc group: "Pattern matching"
  @doc """
  Case-sensitive pattern matching search using [PostgreSQL `LIKE`](https://www.postgresql.org/docs/current/functions-matching.html#FUNCTIONS-LIKE) operator.

  > #### Warning {: .neutral}
  >
  > Doesn't clean the term, so it needs to be sanitized before being passed in. See
  [LIKE-injections](https://githubengineering.com/like-injection/).

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
  defmacro like(query, bindings, qualifiers, term, _opts \\ []) do
    Torus.Search.PatternMatch.like(query, bindings, qualifiers, term)
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
    Torus.Search.PatternMatch.similar_to(query, bindings, qualifiers, term)
  end

  @doc group: "Pattern matching"
  @doc """
  Removes all like/ilike special characters from the term, so it can be used in further pattern-match searches.
  """
  def sanitize(term) do
    Torus.Search.PatternMatch.sanitize(term)
  end

  # -----------------------------------
  # TODO: Add POSIX Regular Expressions
  # -----------------------------------

  @doc group: "Similarity"
  @doc """
  Case-insensitive similarity search using [PostgreSQL similarity functions](https://postgresql.org/docs/current/interactive/pgtrgm.html#PGTRGM-FUNCS-OPS).

  > #### Warning {: .neutral}
  >
  > You need to have pg_trgm extension installed.
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
      - `:full` (default) - uses `similarity` function.
      - `:word` - uses `word_similarity` function. If you're dealing with sentences
      and you don't want the length of the strings to affect the search result.
      - `:strict` - uses `strict_word_similarity` function. Prioritizes full matches,
      forces extent boundaries to match word boundaries. Since we don't have
      cross-word trigrams, this function actually returns greatest similarity between
      first string and any continuous extent of words of the second string.
    * `:order` - describes the ordering of the results. Possible values are
      - `:desc` (default) - orders the results by similarity rank in descending order.
      - `:asc` - orders the results by similarity rank in ascending order.
      - `:none` - doesn't apply ordering and returns
    * `:pre_filter` - whether or not to pre-filter the results:
      - `false` (default) - omits pre-filtering and returns all results.
      - `true` -  before applying the order, pre filters (using boolean
    operators which potentially use GIN indexes) the result set. The results above
    `pg_trgm.similarity_threshold` (which defaults to 0.3) are returned.

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
      ...> |> Torus.similarity([p], [p.title], "what a cloak", pre_filter: true)
      ...> |> select([p], p.title)
      ...> |> Repo.all()
      ["What an amazing cloak"]

  ## Optimizations

  - Use `pre_filter: true` to pre-filter the results before applying the order.
  This would significantly reduce the number of rows to order. The pre-filtering
  phase uses different (boolean) similarity operators which more actively leverage
  GIN indexes.
  - Limit the number of raws returned using `limit`.
  - Use `order: :none` argument if you don't care about the order of the results.
  The query will return all results that are above the similarity threshold, which
  you can set globally via `SET pg_trgm.similarity_threshold = 0.3;`.
  - When `order: :desc` (default) and the limit is not set, the query will do a full
  table scan, so it's recommended to manually limit the results (by applying `where`
  or `limit` clauses to filter the rows as much as possible).

  ### Adding an index

  ```sql
  CREATE EXTENSION IF NOT EXISTS pg_trgm;

  CREATE INDEX index_posts_on_title ON posts USING GIN (title gin_trgm_ops);
  ```
  """
  defmacro similarity(query, bindings, qualifiers, term, opts \\ []) do
    Torus.Search.Similarity.similarity(query, bindings, qualifiers, term, opts)
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
    * `:stored`
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
      - `4` (default for `ts_rank_cs`)  - divides the rank by the mean harmonic
      distance between extents (this is implemented only by `ts_rank_cd`)
      - `8`  - divides the rank by the number of unique words in document
      - `16` -  divides the rank by 1 + the logarithm of the number of unique words in
      document
      - `32` - divides the rank by itself + 1
    * `:order` - describes the ordering of the results. Possible values are
      - `:desc` (default) - orders the results by similarity rank in descending order.
      - `:asc` - orders the results by similarity rank in ascending order.
      - `:none` - doesn't apply ordering at all.
    * `:filter_type`
      - `:or` (default) - uses `OR` operator to combine different column matches.
      Selecting this option means that the search term won't match across columns.
      - `:concat` - joins the columns into a single tsvector and searches for the
      term in the concatenated string containing all columns.
      - `:none` - doesn't apply any filtering and returns all results.
    * `empty_return`
      - `true` (default) - returns all results when the search term is empty.
      - `false` - returns an empty list when the search term is empty.
    * `:coalesce`
      - `true` (default) - when joining columns via `:concat` option, adds a
      `COALESCE` function to handle NULL values. Choose this when you can't guarantee
      that all columns are non-null.
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
    Torus.Search.FullText.full_text(query, bindings, qualifiers, term, opts)
  end

  @doc false
  defmacro to_tsquery(column, query_text, opts \\ []) do
    Torus.Search.FullText.to_tsquery(column, query_text, opts)
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
  Takes a list of terms (binaries) and embedding module's specific options and passes them to `embedding_module` `generate/2` function.

  Configure `embedding_module` either in `config.exs`:

        config :torus, :embedding_module, Torus.Embeddings.HuggingFace

  or pass `embedding_module` as an option to `to_vectors/2` function. Options always
  have greater priority than the config.

  See [Semantic search guide](semantic_search.html) for more info.
  """
  defdelegate to_vectors(terms, opts \\ []), to: Torus.Search.Semantic

  @doc group: "Semantic"
  @doc """
  Same as `to_vectors/2`, but returns the first vector from the list.
  """
  defdelegate to_vector(term, opts \\ []), to: Torus.Search.Semantic

  @doc group: "Semantic"
  @doc """
  Calls the specified embedding module's `embedding_model/1` function to retrieve the model name.

  See [Semantic search guide](semantic_search.html) for more info.
  """
  defdelegate embedding_model(opts \\ []), to: Torus.Search.Semantic

  @doc group: "Semantic"
  @doc """
  Semantic search using pgvector extension to compare vectors. See [Semantic search guide](semantic_search.html) for more info.

  ## Options
    * `:distance` - a way to calculate the distance between the vectors. Can be one of:
      - `:l2_distance` (default) - L2 distance
      - `:max_inner_product` - negative inner product
      - `:cosine_distance` - cosine distance
      - `:l1_distance` - L1 distance
      - `:hamming_distance` - Hamming distance
      - `:jaccard_distance` - Jaccard distance
    * `:order` - describes the ordering of the results. Possible values are
      - `:asc` (default) - orders the results by distance in ascending order. 0 distance means that the vectors are the same meaning the the terms are equal. The closer the vectors - more aligned are the terms.
      - `:desc` - orders the results by distance in descending order.
      - `:none` - doesn't apply ordering at all.
    * `:pre_filter` - a positive float that is passed directly to the query to pre-filter the results.
      - `:none` (default) - no pre-filtering is done.
      - `float` - pre-filters the results before applying the order. The results with vectors distance below the pre-filter value are returned.

  ## Examples

      def search(term) do
        search_vector = Torus.to_vector(term)

        Post
        |> Torus.semantic([p], p.embedding, search_vector)
        |> Repo.all()
      end
  """
  defmacro semantic(query, bindings, qualifier, vector_term, opts \\ []) do
    Torus.Search.Semantic.semantic(query, bindings, qualifier, vector_term, opts)
  end
end
