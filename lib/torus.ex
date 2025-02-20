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
  Case insensitive pattern matching search using [PostgreSQL `ILIKE`](https://www.postgresql.org/docs/current/functions-matching.html#FUNCTIONS-LIKE) operator.

  **Doesn't clean the term, so it needs to be sanitized before being passed in, see [LIKE-injections](https://githubengineering.com/like-injection/)**

  ## Examples

  ```elixir
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
  ```

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

  **Doesn't clean the term, so it needs to be sanitized before being passed in, see [LIKE-injections](https://githubengineering.com/like-injection/)**

  ## Examples

  ```elixir
  iex> insert_post!(title: "hogwarts")
  ...> insert_post!(body: "HOGWARTS")
  ...> Post
  ...> |> Torus.like([p], [p.title, p.body], "%OGWART%")
  ...> |> select([p], p.body)
  ...> |> Repo.all()
  ["HOGWARTS"]
  ```

  ## Optimizations

  - `like` is case-sensitive, so it can take advantage of B-tree indexes when there is no wildcard (%) at the beginning of the search term, prefer it over `ilike` if possible.
  Adding a B-tree index:

  ```sql
  CREATE INDEX index_posts_on_title ON posts (title);
  ```

  - Use `GIN` or `GiST` Index with `pg_trgm`extension for LIKE and ILIKE

    - When searching for substrings (%word%), B-tree indexes won't help. Instead, use trigram indexing (pg_trgm extension).
    - ```sql
      CREATE EXTENSION IF NOT EXISTS pg_trgm;
      CREATE INDEX posts_title_trgm_idx ON posts USING GIN (title gin_trgm_ops);
      ```
  - If using prefix search, convert data to lowercase and Use B-tree Index for Case-Insensitive Search
    - ```sql
      ALTER TABLE posts ADD COLUMN title_lower TEXT GENERATED ALWAYS AS (LOWER(title)) STORED;
      CREATE INDEX index_posts_on_title ON posts (title_lower);
      ```
      ```elixir
      Torus.like([p], [p.title_lower], "hogwarts%")
      ```

  - Use full-text search for large text fields, see `full_text_dynamic/5` for more details.
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
  Similar to `like/5`, except that it interprets the pattern using the SQL standard's definition of a regular expression. SQL regular expressions are a curious cross between LIKE notation and common (POSIX) regular expression notation. See [PostgreSQL `SIMILAR TO`](https://postgresql.org/docs/current/interactive/functions-matching.html?fts_query=ilike#FUNCTIONS-SIMILARTO-REGEXP)

  ## Examples

  ```elixir
  ...> insert_post!(body: "HOGWARTS")
  ...> Post
  ...> |> Torus.ilike([p], [p.title, p.body], "%(Hog|hog)%")
  ...> |> select([p], p.body)
  ...> |> Repo.all()
  [1]
  ```

  ## Optimizations

  TODO
  """
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

  # Trigram concepts

  # TODO: Carry on writing about similarity search
  @doc """
  Case insensitive similarity search using [PostgreSQL `word_similarity`](https://postgresql.org/docs/current/interactive/pgtrgm.html#PGTRGM-FUNCS-OPS).


  **You need to have pg_trgm extension installed.**

  ## Options
    * `strict: true` - uses `strict_word_similarity` instead of `word_similarity`. This means that it forces extent boundaries to match word boundaries. Since we don't have cross-word trigrams, this function actually returns greatest similarity between first string and any continuous extent of words of the second string.

    * `desc: true` - default ordering is descending, set to false for ascending.

  ## Examples

  ```elixir
  iex> insert_post!(title: "Hogwarts Shocker", body: "A spell disrupts the Quidditch Cup.")
  ...> insert_post!(title: "Diagon Bombshell", body: "Secrets uncovered in the heart of Hogwarts.")
  ...> insert_post!(title: "Completely unrelated", body: "No magic here!")
  ...>  Post
  ...> |> Torus.similarity([p], [p.title, p.body], "boshel", limit: 1)
  ...> |> select([p], p.title)
  ...> |> Repo.all()
  ["Diagon Bombshell"]
  ```

  TODO: Add section on optimization, tradeoffs, etc.
  """
  defmacro similarity(query, bindings, qualifiers, term, args \\ []) do
    qualifiers = List.wrap(qualifiers)
    limit = Keyword.get(args, :limit)

    similarity_function =
      (Keyword.get(args, :strict, false) && "strict_word_similarity") || "word_similarity"

    desc_asc = (Keyword.get(args, :desc, true) && "DESC") || "ASC"

    similarity_string = "#{similarity_function}(?, ?) #{desc_asc}"

    Enum.reduce(qualifiers, query, fn qualifier, query ->
      quote do
        query =
          order_by(
            unquote(query),
            [unquote_splicing(bindings)],
            fragment(
              unquote(similarity_string),
              unquote(qualifier),
              unquote(term)
            )
          )

        if unquote(limit) do
          limit(query, ^unquote(limit))
        else
          query
        end
      end
    end)
  end

  @doc """
  Full text prefix search with rank ordering. Accepts a list of columns to search in.
  Cleans the term, so it can be input directly by the user.

  ## Example usage

  ```elixir
  iex> insert_post!(title: "Hogwarts Shocker", body: "A spell disrupts the Quidditch Cup.")
  ...> insert_post!(title: "Diagon Bombshell", body: "Secrets uncovered in the heart of Hogwarts.")
  ...> insert_post!(title: "Completely unrelated", body: "No magic here!")
  ...>  Post
  ...> |> Torus.full_text_dynamic([p], [p.title, p.body], "uncovered hogwarts")
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
  The substring function with three parameters provides extraction of a substring that matches an SQL regular expression pattern. The function can be written according to standard SQL syntax:

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
