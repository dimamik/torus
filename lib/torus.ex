defmodule Torus do
  @external_resource readme = Path.join([__DIR__, "../README.md"])

  @moduledoc readme
             |> File.read!()
             |> String.split("<!-- MDOC -->")
             |> Enum.fetch!(1)

  import Ecto.Query

  @default_language "english"

  ## Similarity searches

  @doc """
  Case-insensitive pattern matching search using
  [PostgreSQL `ILIKE`](https://www.postgresql.org/docs/current/functions-matching.html#FUNCTIONS-LIKE) operator.

  **Doesn't clean the term, so it needs to be sanitized before being passed in. See
  [LIKE-injections](https://githubengineering.com/like-injection/).**


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
  defmacro ilike(query, bindings, qualifiers, term, _args \\ []) do
    qualifiers = List.wrap(qualifiers)

    where_ast =
      Enum.reduce(qualifiers, false, fn qualifier, conditions_acc ->
        quote do
          dynamic(
            [unquote_splicing(bindings)],
            ilike(unquote(qualifier), ^unquote(term)) or ^unquote(conditions_acc)
          )
        end
      end)

    quote do
      where(unquote(query), ^unquote(where_ast))
    end
  end

  @doc """
  Case-sensitive pattern matching search using [PostgreSQL `LIKE`](https://www.postgresql.org/docs/current/functions-matching.html#FUNCTIONS-LIKE) operator.

  **Doesn't clean the term, so it needs to be sanitized before being passed in, see
  [LIKE-injections](https://githubengineering.com/like-injection/)**

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

  - Use full-text search for large text fields, see `full_text_dynamic/5` for more
  details.
  """
  defmacro like(query, binding, qualifiers, term, _args \\ []) do
    qualifiers = List.wrap(qualifiers)

    where_ast =
      Enum.reduce(qualifiers, false, fn qualifier, conditions_acc ->
        quote do
          dynamic(
            [unquote_splicing(binding)],
            like(unquote(qualifier), ^unquote(term)) or ^unquote(conditions_acc)
          )
        end
      end)

    quote do
      where(unquote(query), ^unquote(where_ast))
    end
  end

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
  defmacro similar_to(query, bindings, qualifiers, term, _args \\ []) do
    qualifiers = List.wrap(qualifiers)

    where_ast =
      Enum.reduce(qualifiers, false, fn qualifier, conditions_acc ->
        quote do
          dynamic(
            [unquote_splicing(bindings)],
            operator(unquote(qualifier), "SIMILAR TO", ^unquote(term)) or ^unquote(conditions_acc)
          )
        end
      end)

    quote do
      where(unquote(query), ^unquote(where_ast))
    end
  end

  # -----------------------------------
  # TODO: Add POSIX Regular Expressions
  # -----------------------------------

  @similarity_types ~w[word strict full]a
  @similarity_order_types ~w[desc asc none]a
  @true_false ~w[true false]a
  @doc """
  Case-insensitive similarity search using [PostgreSQL similarity functions](https://postgresql.org/docs/current/interactive/pgtrgm.html#PGTRGM-FUNCS-OPS).

  **You need to have pg_trgm extension installed.**

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
    * `:limit` - limits the number of results returned (PostgreSQL `LIMIT`). By
    default limit is not applied and the results are above
    `pg_trgm.similarity_threshold`, which defaults to 0.3.
    * `:pre_filter` - whether or not to pre-filter the results:
      - `false` (default) - omits pre-filtering and returns all results.
      - `true` -  before applying the order, pre filters (using boolean
    operators which potentially use GIN indexes) the result set.

  ## Examples

      iex> insert_post!(title: "Hogwarts Shocker", body: "A spell disrupts the Quidditch Cup.")
      ...> insert_post!(title: "Diagon Bombshell", body: "Secrets uncovered in the heart of Hogwarts.")
      ...> insert_post!(title: "Completely unrelated", body: "No magic here!")
      ...>  Post
      ...> |> Torus.similarity([p], [p.title, p.body], "Diagon Bombshell", limit: 1)
      ...> |> select([p], p.title)
      ...> |> Repo.all()
      ["Diagon Bombshell"]

      iex> insert_posts!(["Wand", "Owl", "What an amazing cloak"])
      ...> Post
      ...> |> Torus.similarity([p], [p.title], "what a cloak", pre_filter: true)
      ...> |> select([p], p.title)
      ...> |> Repo.all()
      ["What an amazing cloak"]

      iex> insert_posts!(["Magic wand", "Wand", "Owlyth"])
      ...> Post
      ...> |> Torus.similarity([p], [p.title], "wand", pre_filter: true)
      ...> |> select([p], p.title)
      ...> |> Repo.all()
      ["Wand", "Magic wand"]

  ## Optimizations

  - Use `pre_filter: true` to pre-filter the results before applying the order.
  This would significantly reduce the number of rows to order. The pre-filtering
  phase uses different (boolean) similarity operators which more actively leverage
  GIN indexes.
  - Use `limit` to limit the number of results returned.
  - Use `order: `:none` argument if you don't care about the order of the results.
  The query will return all results that are above the similarity threshold, which
  you can set globally via `SET pg_trgm.similarity_threshold = 0.3;`.
  - When `order: `:desc` (default) and the limit is not set, the query will do a full
  table scan, so it's recommended to manually limit the results (by applying `where`
  clauses to as little rows as possible).

  ### Adding an index

  ```sql
  CREATE EXTENSION IF NOT EXISTS pg_trgm;

  CREATE INDEX index_posts_on_title ON posts USING GIN (title gin_trgm_ops);
  ```

  ## Already implemented optimizations

  - Instead of scanning all rows and computing similarity for each, we first filter
  with `%` (which could use a GIN index), and next we compute (potentially expensive)
  the ranks using `similarity` function and order the results.
  """
  # TODO: Add `:join_type` argument
  # I'll fix the complexity, I promise!
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defmacro similarity(query, bindings, qualifiers, term, args \\ []) do
    # Arguments validation
    qualifiers = List.wrap(qualifiers)
    limit = Keyword.get(args, :limit)
    pre_filter = get_arg!(args, :pre_filter, false, @true_false)

    if not is_nil(limit) and not is_integer(limit) do
      raise """
      `:limit` should be an integer. Got: #{inspect(limit)}
      """
    end

    similarity_type = get_arg!(args, :type, :full, @similarity_types)
    order = get_arg!(args, :order, :desc, @similarity_order_types)

    # Arguments preparation
    {similarity_function, operator} =
      case similarity_type do
        :strict -> {"strict_word_similarity", "<<%"}
        :word -> {"word_similarity", "<%"}
        :full -> {"similarity", "%"}
      end

    desc_asc = order |> to_string() |> String.upcase()
    similarity_string = "#{similarity_function}(?, ?) #{desc_asc}"
    multiple_qualifiers = length(qualifiers) > 1
    has_order = order != :none

    # Query building
    quote do
      unquote(query)
      |> apply_if(unquote(pre_filter) and unquote(multiple_qualifiers), fn query ->
        where(
          query,
          [unquote_splicing(bindings)],
          operator(^unquote(term), unquote(operator), concat_ws(" ", unquote(qualifiers)))
        )
      end)
      |> apply_if(unquote(pre_filter) and not unquote(multiple_qualifiers), fn query ->
        where(
          query,
          [unquote_splicing(bindings)],
          operator(^unquote(term), unquote(operator), unquote(List.first(qualifiers)))
        )
      end)
      |> apply_if(unquote(has_order) and unquote(multiple_qualifiers), fn query ->
        order_by(
          query,
          [unquote_splicing(bindings)],
          fragment(unquote(similarity_string), unquote(term), concat_ws(" ", unquote(qualifiers)))
        )
      end)
      |> apply_if(unquote(has_order) and not unquote(multiple_qualifiers), fn query ->
        order_by(
          query,
          [unquote_splicing(bindings)],
          fragment(unquote(similarity_string), unquote(term), unquote(List.first(qualifiers)))
        )
      end)
      |> apply_if(unquote(limit), &limit(&1, ^unquote(limit)))
    end
  end

  # ----------------------------------------------------------------
  # TODO: Combine different types of searches (or at least show how)
  # ----------------------------------------------------------------

  @supported_weights ~w[A B C D]
  @term_functions ~w[websearch_to_tsquery plainto_tsquery phraseto_tsquery]a
  @rank_functions ~w[ts_rank_cd ts_rank]a
  @filter_types ~w[or concat none]a

  @doc """
  Full text search with rank ordering. Accepts a list of columns to search in.
  Cleans the term, so it can be input directly by the user. The default preset of
  settings is optimal for most cases.

  ## Options
    * `:language` - language used for the search. Defaults to `"english"`.
    * `:prefix_search` - whether to apply prefix search.
      - `true` (default) - the term is treated as a prefix
      - `false` - only counts full-word matches
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
    * `:nullable_columns` - a list of columns which values can take `null`s, so that
    they can be escaped during the search. Defaults to all qualifiers. When passed -
    speeds up the search. For example `[p.title, a.first_name]` would mean that only
    `p.title` and `a.first_name` columns can take `null`s, whereas other columns are
    guaranteed by the caller to be non-nullable.

  ## Example usage

      iex> insert_post!(title: "Hogwarts Shocker", body: "A spell disrupts the Quidditch Cup.")
      ...> insert_post!(title: "Diagon Bombshell", body: "Secrets uncovered in the heart of Hogwarts.")
      ...> insert_post!(title: "Completely unrelated", body: "No magic here!")
      ...>  Post
      ...> |> Torus.full_text_dynamic([p], [p.title, p.body], "uncov hogwar", filter_type: :concat)
      ...> |> select([p], p.title)
      ...> |> Repo.all()
      ["Diagon Bombshell"]

  ## Optimizations

    - Store precomputed tsvector in a separate column, add a GIN index to it, and use
    `full_text_stored/5`. See more on how to add an index and how to store a column in
    the `full_text_stored/5` docs. If that's not feasible, read on.

    - Pass implicitly `nullable_columns` so that we're leveraging existing non-coalesce
    GIN indexes (if present) and are not doing unneeded work.

    - Add a GIN ts_vector index on the column(s) you search in.
    Use `Torus.QueryInspector.tap_sql/2` on your query (with all the options passed) to see the exact search string and add an index to it. For example for nullable title, the GIN index could look like:

      ```sql
      CREATE INDEX index_gin_posts_title
      ON posts USING GIN (to_tsvector('english', COALESCE(title, '')));
      ```
  """
  defmacro full_text_dynamic(query, bindings, qualifiers, term, args \\ []) do
    # Arguments validation
    qualifiers = List.wrap(qualifiers)
    language = get_language(args)
    prefix_search = get_arg!(args, :prefix_search, true, @true_false)
    term_function = get_arg!(args, :term_function, :websearch_to_tsquery, @term_functions)
    rank_function = get_arg!(args, :rank_function, :ts_rank_cd, @rank_functions)
    filter_type = get_arg!(args, :filter_type, :or, @filter_types)
    nullable_columns = Keyword.get(args, :nullable_columns, qualifiers)
    order = get_arg!(args, :order, :desc, @similarity_order_types)

    rank_weights =
      Keyword.get_lazy(args, :rank_weights, fn ->
        exceeding_size = max(length(qualifiers) - 4, 0)
        [:A, :B, :C, :D] ++ List.duplicate(:D, exceeding_size)
      end)

    if length(rank_weights) < length(qualifiers) do
      raise """
      The length of `rank_weights` should be the same as the length of the qualifiers.
      """
    end

    if not Enum.all?(rank_weights, &(to_string(&1) in @supported_weights)) do
      raise """
      Each rank weight from `rank_weights` should be one of the: #{@supported_weights}
      """
    end

    rank_normalization =
      Keyword.get_lazy(args, :rank_normalization, fn ->
        if rank_function == :ts_rank_cd, do: 4, else: 1
      end)

    # Arguments preparation
    prefix_search = if prefix_search, do: "::text || ':*'", else: ""
    desc_asc = order |> to_string() |> String.upcase()
    has_order = order != :none

    weights_prepared =
      qualifiers
      |> Enum.with_index()
      |> Enum.map_join(" || ", fn {qualifier, index} ->
        weight = Enum.fetch!(rank_weights, index)
        coalesce = if qualifier in nullable_columns, do: "COALESCE(?, '')", else: "?"
        "setweight(to_tsvector(#{language}, #{coalesce}), '#{weight}')"
      end)

    # TODO: Check if the trim is needed?
    concat_filter_string =
      "#{weights_prepared} @@ (#{term_function}(#{language}, ?)#{prefix_search})::tsquery"

    concat_filter_fragment =
      quote do
        fragment(
          unquote(concat_filter_string),
          unquote_splicing(qualifiers),
          ^unquote(term)
        )
      end

    order_string = """
    #{rank_function}(#{weights_prepared}, #{term_function}(#{language}, ?), #{rank_normalization}) #{desc_asc}
    """

    order_fragment =
      quote do
        fragment(
          unquote(order_string),
          unquote_splicing(qualifiers),
          ^unquote(term)
        )
      end

    or_filter_ast =
      Enum.reduce(qualifiers, false, fn qualifier, conditions_acc ->
        quote do
          dynamic(
            [unquote_splicing(bindings)],
            to_tsquery_dynamic(unquote(qualifier), ^unquote(term), unquote(args)) or
              ^unquote(conditions_acc)
          )
        end
      end)

    # Query building
    quote do
      unquote(query)
      |> apply_case(
        unquote(filter_type),
        fn
          :none, query ->
            query

          :or, query ->
            where(unquote(query), ^unquote(or_filter_ast))

          :concat, query ->
            where(unquote(query), [unquote_splicing(bindings)], unquote(concat_filter_fragment))
        end
      )
      |> apply_if(unquote(has_order), fn query ->
        order_by(
          query,
          [unquote_splicing(bindings)],
          unquote(order_fragment)
        )
      end)
    end
  end

  @doc false
  defmacro to_tsquery_dynamic(column, query_text, args \\ []) do
    term_function = get_arg!(args, :term_function, :websearch_to_tsquery, @term_functions)
    prefix_search = if Keyword.get(args, :prefix_search, true), do: "::text || ':*'", else: ""

    fragment_string =
      """
      CASE
          WHEN trim(#{term_function}(?, ?)::text) = '' THEN FALSE
          ELSE to_tsvector(?, ?) @@ (#{term_function}(?, ?)#{prefix_search})::tsquery
      END
      """

    quote do
      fragment(
        unquote(fragment_string),
        unquote(@default_language),
        unquote(query_text),
        unquote(@default_language),
        unquote(column),
        unquote(@default_language),
        unquote(query_text)
      )
    end
  end

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
  # TODO: Fix the doctest. For now this test is duped in the test file.
  defmacro substring(string, pattern, escape_character) do
    quote do
      fragment(
        "substring(? similar ? escape ?)",
        unquote(string),
        unquote(pattern),
        unquote(escape_character)
      )
    end
  end

  # Private helpers

  @doc false
  defmacro operator(a, operator, b) do
    quote do
      fragment(
        unquote("? #{operator} ?"),
        unquote(a),
        unquote(b)
      )
    end
  end

  @doc false
  def apply_if(query, condition, query_fun) do
    if condition, do: query_fun.(query), else: query
  end

  def apply_case(query, case_condition, query_fun) do
    query_fun.(case_condition, query)
  end

  @doc false
  defmacro concat_ws(separator, qualifiers) do
    fragment_string = "concat_ws(?" <> String.duplicate(", ?", length(qualifiers)) <> ")"

    quote do
      fragment(
        unquote(fragment_string),
        unquote(separator),
        unquote_splicing(qualifiers)
      )
    end
  end

  defp get_language(args) do
    args |> Keyword.get(:language, @default_language) |> then(&("'" <> &1 <> "'"))
  end

  defp get_arg!(args, value_key, value_default, supported_values) do
    value = Keyword.get(args, value_key, value_default)

    if value not in supported_values do
      raise """
      The value of `#{value_key}` should be one of the: #{supported_values}
      """
    end

    value
  end
end
