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
  @order_types ~w[desc asc none]a
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

  ## Optimizations

  - Use `pre_filter: true` to pre-filter the results before applying the order.
  This would significantly reduce the number of rows to order. The pre-filtering
  phase uses different (boolean) similarity operators which more actively leverage
  GIN indexes.
  - Use `limit` to limit the number of results returned.
  - Use `order: :none` argument if you don't care about the order of the results.
  The query will return all results that are above the similarity threshold, which
  you can set globally via `SET pg_trgm.similarity_threshold = 0.3;`.
  - When `order: :desc` (default) and the limit is not set, the query will do a full
  table scan, so it's recommended to manually limit the results (by applying `where`
  clauses to limit the rows as much as possible).

  ### Adding an index

  ```sql
  CREATE EXTENSION IF NOT EXISTS pg_trgm;

  CREATE INDEX index_posts_on_title ON posts USING GIN (title gin_trgm_ops);
  ```
  """
  defmacro similarity(query, bindings, qualifiers, term, args \\ []) do
    # Arguments fetching
    limit = Keyword.get(args, :limit)
    order = get_arg!(args, :order, :desc, @order_types)
    pre_filter = get_arg!(args, :pre_filter, false, @true_false)
    qualifiers = List.wrap(qualifiers)
    similarity_type = get_arg!(args, :type, :full, @similarity_types)

    # Arguments validation
    raise_if(
      not is_nil(limit) and not is_integer(limit),
      "`:limit` should be an integer. Got: #{inspect(limit)}"
    )

    # Arguments preparation
    {similarity_function, similarity_operator} =
      case similarity_type do
        :full -> {"similarity", "%"}
        :strict -> {"strict_word_similarity", "<<%"}
        :word -> {"word_similarity", "<%"}
      end

    desc_asc_string = descending_ascending(order)
    similarity_function = "#{similarity_function}(?, ?) #{desc_asc_string}"
    multiple_qualifiers = length(qualifiers) > 1
    has_order = order != :none

    # Query building
    quote do
      unquote(query)
      |> apply_if(unquote(pre_filter) and unquote(multiple_qualifiers), fn query ->
        where(
          query,
          [unquote_splicing(bindings)],
          operator(^unquote(term), unquote(similarity_operator), concat_ws(unquote(qualifiers)))
        )
      end)
      |> apply_if(unquote(pre_filter) and not unquote(multiple_qualifiers), fn query ->
        where(
          query,
          [unquote_splicing(bindings)],
          operator(^unquote(term), unquote(similarity_operator), unquote(List.first(qualifiers)))
        )
      end)
      |> apply_if(unquote(has_order) and unquote(multiple_qualifiers), fn query ->
        order_by(
          query,
          [unquote_splicing(bindings)],
          fragment(unquote(similarity_function), ^unquote(term), concat_ws(unquote(qualifiers)))
        )
      end)
      |> apply_if(unquote(has_order) and not unquote(multiple_qualifiers), fn query ->
        order_by(
          query,
          [unquote_splicing(bindings)],
          fragment(unquote(similarity_function), ^unquote(term), unquote(List.first(qualifiers)))
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

  Full Text Searching (or just text search) provides the capability to identify
  natural-language documents that satisfy a query, and optionally to sort them by
  relevance to the query. The most common type of search is to find all documents
  containing given query terms and return them in order of their similarity to the query.
  Notions of query and similarity are very flexible and depend on the specific application.
  The simplest search considers query as a set of words and similarity as the frequency of
  query words in the document. Read more in [PostgreSQL Full Text Search docs](https://postgresql.org/docs/current/interactive/textsearch-intro.html).

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
    * `:concat`
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
      ...> |> Torus.full_text_dynamic([p], [p.title, p.body], "uncov hogwar")
      ...> |> select([p], p.title)
      ...> |> Repo.all()
      ["Diagon Bombshell"]

  ## Optimizations

    - Store precomputed tsvector in a separate column, add a GIN index to it, and use
    `full_text_stored/5`. See more on how to add an index and how to store a column in
    the `full_text_stored/5` docs. If that's not feasible, read on.

    - Add a GIN ts_vector index on the column(s) you search in.
    Use `Torus.QueryInspector.tap_sql/2` on your query (with all the options passed) to see the exact search string and add an index to it. For example for nullable title, the GIN index could look like:

      ```sql
      CREATE INDEX index_gin_posts_title
      ON posts USING GIN (to_tsvector('english', COALESCE(title, '')));
      ```
  """
  defmacro full_text_dynamic(query, bindings, qualifiers, term, args \\ []) do
    # Arguments fetching
    qualifiers = List.wrap(qualifiers)
    language = get_language(args)
    prefix_search = get_arg!(args, :prefix_search, true, @true_false)
    term_function = get_arg!(args, :term_function, :websearch_to_tsquery, @term_functions)
    rank_function = get_arg!(args, :rank_function, :ts_rank_cd, @rank_functions)
    filter_type = get_arg!(args, :filter_type, :or, @filter_types)
    order = get_arg!(args, :order, :desc, @order_types)

    rank_weights =
      Keyword.get_lazy(args, :rank_weights, fn ->
        exceeding_size = max(length(qualifiers) - 4, 0)
        [:A, :B, :C, :D] ++ List.duplicate(:D, exceeding_size)
      end)

    rank_normalization =
      Keyword.get_lazy(args, :rank_normalization, fn ->
        if rank_function == :ts_rank_cd, do: 4, else: 1
      end)

    coalesce = Keyword.get(args, :concat, filter_type == :concat and length(qualifiers) > 1)
    coalesce = coalesce and filter_type == :concat and length(qualifiers) > 1

    # Arguments validation
    raise_if(
      length(rank_weights) < length(qualifiers),
      "The length of `rank_weights` should be the same as the length of the qualifiers."
    )

    raise_if(
      not Enum.all?(rank_weights, &(to_string(&1) in @supported_weights)),
      "Each rank weight from `rank_weights` should be one of the: #{@supported_weights}"
    )

    # Arguments preparation
    prefix_string = prefix_search_string(prefix_search)
    desc_asc = descending_ascending(order)
    has_order = order != :none
    weighted_columns = prepare_weights(qualifiers, language, rank_weights, coalesce)

    concat_filter_string =
      "#{weighted_columns} @@ (#{term_function}(#{language}, ?)#{prefix_string})::tsquery"

    concat_filter_fragment =
      if prefix_search do
        # We need to handle empty strings for prefix search queries
        concat_filter_string = """
        CASE
            WHEN trim(#{term_function}(#{language}, ?)::text) = '' THEN FALSE
            ELSE #{concat_filter_string}
        END
        """

        quote do
          fragment(
            unquote(concat_filter_string),
            ^unquote(term),
            unquote_splicing(qualifiers),
            ^unquote(term)
          )
        end
      else
        quote do
          fragment(
            unquote(concat_filter_string),
            unquote_splicing(qualifiers),
            ^unquote(term)
          )
        end
      end

    order_string =
      "#{rank_function}(#{weighted_columns}, (#{term_function}(#{language}, ?)#{prefix_string})::tsquery, #{rank_normalization})"

    order_fragment =
      if prefix_search do
        # We need to handle empty strings for prefix search queries
        order_string = """
        (CASE
            WHEN trim(#{term_function}(#{language}, ?)::text) = '' THEN 1
            ELSE #{order_string}
        END) #{desc_asc}
        """

        quote do
          fragment(
            unquote(order_string),
            ^unquote(term),
            unquote_splicing(qualifiers),
            ^unquote(term)
          )
        end
      else
        order_string = "#{order_string} #{desc_asc}"

        quote do
          fragment(unquote(order_string), unquote_splicing(qualifiers), ^unquote(term))
        end
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
        order_by(query, [unquote_splicing(bindings)], unquote(order_fragment))
      end)
    end
  end

  @doc false
  defmacro to_tsquery_dynamic(column, query_text, args \\ []) do
    language = get_language(args)
    prefix_search = get_arg!(args, :prefix_search, true, @true_false)
    prefix_string = prefix_search_string(prefix_search)
    term_function = get_arg!(args, :term_function, :websearch_to_tsquery, @term_functions)

    ts_vector_match_string =
      "to_tsvector(#{language}, ?) @@ (#{term_function}(#{language}, ?)#{prefix_string})::tsquery"

    if prefix_search do
      ts_vector_match_string = """
      CASE
          WHEN trim(#{term_function}(#{language}, ?)::text) = '' THEN FALSE
          ELSE #{ts_vector_match_string}
      END
      """

      quote do
        fragment(
          unquote(ts_vector_match_string),
          unquote(query_text),
          unquote(column),
          unquote(query_text)
        )
      end
    else
      quote do
        fragment(
          unquote(ts_vector_match_string),
          unquote(column),
          unquote(query_text)
        )
      end
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
        ^unquote(pattern),
        ^unquote(escape_character)
      )
    end
  end

  # Private helpers

  # Macros

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

  # Functions

  @doc false
  def apply_if(query, condition, query_fun) do
    if condition, do: query_fun.(query), else: query
  end

  @doc false
  def apply_case(query, case_condition, query_fun) do
    query_fun.(case_condition, query)
  end

  defp prefix_search_string(prefix_search) when is_boolean(prefix_search) do
    if prefix_search, do: "::text || ':*'", else: ""
  end

  defp descending_ascending(order) when order in @order_types do
    order |> to_string() |> String.upcase()
  end

  defp prepare_weights(qualifiers, language, rank_weights, coalesce) do
    qualifiers
    |> Enum.with_index()
    |> Enum.map_join(" || ", fn {_qualifier, index} ->
      weight = Enum.fetch!(rank_weights, index)
      coalesce = if coalesce, do: "COALESCE(?, '')", else: "?"
      "setweight(to_tsvector(#{language}, #{coalesce}), '#{weight}')"
    end)
  end

  defp raise_if(condition, message) do
    if condition, do: raise(message)
  end

  defp get_language(args) do
    args |> Keyword.get(:language, @default_language) |> then(&("'" <> &1 <> "'"))
  end

  defp get_arg!(args, value_key, value_default, supported_values) do
    value = Keyword.get(args, value_key, value_default)

    raise_if(
      value not in supported_values,
      "The value of `#{value_key}` should be one of the: #{inspect(supported_values)}"
    )

    value
  end
end
