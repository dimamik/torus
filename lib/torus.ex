defmodule Torus do
  @external_resource readme = Path.join([__DIR__, "../README.md"])

  @moduledoc readme
             |> File.read!()
             |> String.split("<!-- MDOC -->")
             |> Enum.fetch!(1)

  import Ecto.Query
  import Torus.PostgresMacros

  @default_language "english"

  ## Similarity searches

  @doc """
  Case insensitive pattern matching search using
  [PostgreSQL `ILIKE`](https://www.postgresql.org/docs/current/functions-matching.html#FUNCTIONS-LIKE) operator.

  **Doesn't clean the term, so it needs to be sanitized before being passed in, see
  [LIKE-injections](https://githubengineering.com/like-injection/)**

  ## Examples

      iex> insert_posts!(["Wand", "Magic wand", "Owl"])
      ...> Post
      ...> |> Torus.ilike([p], [p.title], "wan%")
      ...> |> select([p], p.title)
      ...> |> Repo.all()
      ["Wand"]

      iex> insert_post!(title: "hogwarts")
      ...> insert_post!(body: "HOGWARTS")
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
  Case sensitive pattern matching search using [PostgreSQL `LIKE`](https://www.postgresql.org/docs/current/functions-matching.html#FUNCTIONS-LIKE) operator.

  **Doesn't clean the term, so it needs to be sanitized before being passed in, see
  [LIKE-injections](https://githubengineering.com/like-injection/)**

  ## Examples

      iex> insert_post!(title: "hogwarts")
      ...> insert_post!(body: "HOGWARTS")
      ...> Post
      ...> |> Torus.like([p], [p.title, p.body], "%OGWART%")
      ...> |> select([p], p.body)
      ...> |> Repo.all()
      ["HOGWARTS"]

  ## Optimizations

  - `like` is case-sensitive, so it can take advantage of B-tree indexes when there
  is no wildcard (%) at the beginning of the search term, prefer it over `ilike` if
  possible.

  Adding a B-tree index:

  ```sql
  CREATE INDEX index_posts_on_title ON posts (title);
  ```

  - Use `GIN` or `GiST` Index with `pg_trgm`extension for LIKE and ILIKE

    - When searching for substrings (%word%), B-tree indexes won't help. Instead,
    use trigram indexing (pg_trgm extension).
    - ```sql
      CREATE EXTENSION IF NOT EXISTS pg_trgm;
      CREATE INDEX posts_title_trgm_idx ON posts USING GIN (title gin_trgm_ops);
      ```
  - If using prefix search, convert data to lowercase and use B-tree index for
    case-insensitive search
    - ```sql
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

      iex> insert_posts!(["Magic wand", "Wand", "Owl"])
      ...> Post
      ...> |> Torus.similarity([p], [p.title], "want", limit: 2)
      ...> |> select([p], p.title)
      ...> |> Repo.all()
      ["Wand", "Magic wand"]

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

  @doc """
  Case insensitive similarity search using [PostgreSQL `word_similarity`](https://postgresql.org/docs/current/interactive/pgtrgm.html#PGTRGM-FUNCS-OPS).

  **You need to have pg_trgm extension installed.**

  ## Options

    * `:type` - similarity type. Defaults to `word`. Possible options are:
      - `:word` - uses `word_similarity` function. If you're dealing with sentences
      and you don't want the length of the strings to affect the search result.
      - `:strict` - uses `strict_word_similarity` function. Prioritizes full matches,
      forces extent boundaries to match word boundaries. Since we don't have
      cross-word trigrams, this function actually returns greatest similarity between
      first string and any continuous extent of words of the second string.
      - `:full` - uses `similarity` function.
    * `:asc` - sets the ordering to ascending. Defaults to descending.
    * `:limit` - limits the number of results returned (PostgreSQL `LIMIT`). By
    default limit is not applied.
    * `:order` - when false, uses boolean operators and returns (unordered) all
    results that are above `pg_trgm.similarity_threshold`, which default 0.3. When
    set to true, the results are ordered by similarity rank. Defaults to true.
    * `:pre_filter` - before ordering (if at all), pre filters (using boolean
    operators which potentially use GIN indexes) the result set. Omits pre-filtering
    if false. Defaults to true.

  ## Examples

      iex> insert_post!(title: "Hogwarts Shocker", body: "A spell disrupts the Quidditch Cup.")
      ...> insert_post!(title: "Diagon Bombshell", body: "Secrets uncovered in the heart of Hogwarts.")
      ...> insert_post!(title: "Completely unrelated", body: "No magic here!")
      ...>  Post
      ...> |> Torus.similarity([p], [p.title, p.body], "boshel", limit: 1)
      ...> |> select([p], p.title)
      ...> |> Repo.all()
      ["Diagon Bombshell"]

      iex> insert_posts!(["Wand", "Owl", "What an amazing cloak"])
      ...> Post
      ...> |> Torus.full_text_dynamic([p], [p.title], "what a cloak")
      ...> |> select([p], p.title)
      ...> |> Repo.all()
      ["What an amazing cloak"]


  ## Optimizations

  - Use `limit` to limit the number of results returned.
  - Use `order: false` argument if you don't care about the order of the results.
  The query will return all results that are above the similarity threshold, which
  you can set globally via `SET pg_trgm.similarity_threshold = 0.3;`.
  - When `order: true` (default) and the limit is not set, the query will do a full
  table scan, so it's recommended to set as low `limit` as possible.


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
  defmacro similarity(query, bindings, qualifiers, term, args \\ []) do
    qualifiers = List.wrap(qualifiers)
    limit = Keyword.get(args, :limit)

    {similarity_function, operator} =
      case Keyword.get(args, :type, :word) do
        :word -> {"word_similarity", "<%"}
        :strict -> {"strict_word_similarity", "<<%"}
        :full -> {"similarity", "%"}
      end

    desc_asc = (Keyword.get(args, :asc, false) && "ASC") || "DESC"
    similarity_string = "#{similarity_function}(?, ?) #{desc_asc}"

    Enum.reduce(qualifiers, query, fn qualifier, query ->
      quote do
        query =
          if Keyword.get(unquote(args), :pre_filter, true) do
            where(
              unquote(query),
              [unquote_splicing(bindings)],
              operator(
                unquote(qualifier),
                unquote(operator),
                unquote(term)
              )
            )
          else
            unquote(query)
          end

        query =
          if Keyword.get(unquote(args), :order, true) do
            order_by(
              unquote(query),
              [unquote_splicing(bindings)],
              fragment(
                unquote(similarity_string),
                unquote(qualifier),
                unquote(term)
              )
            )
          else
            query
          end

        if unquote(limit), do: limit(query, ^unquote(limit)), else: query
      end
    end)
  end

  # ----------------------------------------------------------------
  # TODO: Combine different types of searches (or at least show how)
  # ----------------------------------------------------------------

  # TODO: Improve the docs on full-text search
  @doc """
  Full text prefix search with rank ordering. Accepts a list of columns to search in.
  Cleans the term, so it can be input directly by the user.

  ## Example usage

  ```elixir
  iex> insert_post!(title: "Hogwarts Shocker", body: "A spell disrupts the Quidditch Cup.")
  ...> insert_post!(title: "Diagon Bombshell", body: "Secrets uncovered in the heart of Hogwarts.")
  ...> insert_post!(title: "Completely unrelated", body: "No magic here!")
  ...>  Post
  ...> |> Torus.full_text_dynamic([p], [p.title, p.body], "uncov hogwar")
  ...> |> select([p], p.title)
  ...> |> Repo.all()
  ["Diagon Bombshell"]
  ```

  TODO: Add section on optimization, tradeoffs, etc.
  """
  defmacro full_text_dynamic(query, bindings, qualifiers, term, args \\ []) do
    language = language(args)
    qualifiers = List.wrap(qualifiers)

    where_ast =
      Enum.reduce(qualifiers, false, fn qualifier, conditions_acc ->
        quote do
          dynamic(
            [unquote_splicing(bindings)],
            to_tsquery_dynamic(unquote(qualifier), ^unquote(term)) or
              ^unquote(conditions_acc)
          )
        end
      end)

    weights_prepared =
      qualifiers
      |> Enum.with_index()
      |> Enum.map_join(" || ", fn {_qualifier, index} ->
        "setweight(to_tsvector(#{language}, COALESCE(?, '')), '#{<<index + 65::utf8>>}')"
      end)

    fragment_string = """
    ts_rank(#{weights_prepared}, websearch_to_tsquery(#{language}, ?)) DESC
    """

    fragment_prepared =
      quote do
        fragment(
          unquote(fragment_string),
          unquote_splicing(qualifiers),
          ^unquote(term)
        )
      end

    quote do
      unquote(query)
      |> where(^unquote(where_ast))
      |> order_by(
        [unquote_splicing(bindings)],
        unquote(fragment_prepared)
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

  @doc """
  Use any postgres operator in a query.
  """
  defmacro operator(a, operator, b) do
    quote do
      fragment(
        unquote("? #{operator} ?"),
        unquote(a),
        unquote(b)
      )
    end
  end

  defp language(args) do
    args |> Keyword.get(:language, @default_language) |> then(&("'" <> &1 <> "'"))
  end
end
