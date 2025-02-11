defmodule Torus do
  @moduledoc """
  Torus bridges Ecto and PostgreSQL, simplifying building search queries.

  ## Usage

  With just a few lines of code, you can implement a full text search:

  ```elixir
  Post
  |> Torus.full_text_dynamic([p], [p.title, p.body], "uncovered hogwarts")
  |> Repo.all()
  ```

  ## 5 types of searches:

  1. **Similarity**: Searches for items that are closely alike based on attributes, often using measures like cosine similarity or Euclidean distance.

  2. **Text Search Vectors**: Uses term-document matrix vectors for **full-text search**, enabling
  efficient querying and ranking based on term frequency.
      - [PostgreSQL: Documentation: 17: Chapter 12. Full Text Search](https://www.postgresql.org/docs/current/textsearch.html)
      ```sql
      SELECT to_tsvector('english', 'The quick brown fox jumps over the lazy dog') @@ to_tsquery('fox & dog');
      ```
  3. **Semantic Search**: Understands the contextual meaning of queries to match and retrieve related content, often utilizing natural language processing.
    [Semantic Search with PostgreSQL and OpenAI Embeddings | by Dima Timofeev | Towards Data Science](https://towardsdatascience.com/semantic-search-with-postgresql-and-openai-embeddings-4d327236f41f)
  4. **Hybrid Search**: Combines multiple search techniques (e.g., keyword and semantic) to leverage their strengths for more accurate results.
  5. **3rd Party Engines/Providers**: Utilizes external services or software specifically designed for optimized and scalable search capabilities, such as Elasticsearch or Algolia.

  ## Torus support

  For now, Torus supports similarity and full text search, with a plan to expand the support further. These docs will be updated with more examples on where to pick which search type and how to make them more performant (by adding indexes or using specific functions).
  """

  import Ecto.Query

  @default_language "english"

  @doc """
  Wrapper around postgres `ilike` function. Accepts a list of columns to search in.

  **Doesn't clean the term, so it needs to be sanitized before being passed in.**

  ## Examples

  ```elixir
  iex> insert_post!(title: "Hogwarts Shocker", body: "A spell disrupts the Quidditch Cup.")
  ...> insert_post!(title: "Diagon Bombshell", body: "Secrets uncovered in the heart of Hogwarts.")
  ...> insert_post!(title: "Completely unrelated", body: "No magic here!")
  ...> Post
  ...> |> Torus.ilike([p], [p.title, p.body], "%ogw%")
  ...> |> select([p], p.title)
  ...> |> order_by(:id)
  ...> |> Repo.all()
  ["Hogwarts Shocker", "Diagon Bombshell"]
  ```

  TODO: Add section on optimization, tradeoffs, etc.
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
  Wrapper around postgres `similarity` function. Accepts a list of columns to search in.

  **You need to have pg_trgm extension installed.**

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

  [Similarity search in postgres](https://postgresql.org/docs/17/interactive/pgtrgm.html#//apple_ref/cpp/Function/similarity).

  TODO: Add section on optimization, tradeoffs, etc.
  """
  defmacro similarity(query, bindings, qualifiers, term, args \\ []) do
    qualifiers = List.wrap(qualifiers)
    limit = Keyword.get(args, :limit)

    Enum.reduce(qualifiers, query, fn qualifier, query ->
      quote do
        query =
          order_by(
            unquote(query),
            [unquote_splicing(bindings)],
            fragment("similarity(?, ?) DESC", unquote(qualifier), unquote(term))
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
  Full text search with rank ordering. Accepts a list of columns to search in.
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
            to_tsquery_dynamic(unquote(qualifier), ^unquote(term)) or ^unquote(conditions_acc)
          )
        end
      end)

    weights_prepared =
      qualifiers
      |> Enum.with_index()
      |> Enum.map(fn {_qualifier, index} ->
        "setweight(to_tsvector(#{language}, COALESCE(?, '')), '#{<<index + 65::utf8>>}')"
      end)
      |> Enum.join(" || ")

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

  defmacro to_tsquery_dynamic(column, query_text, language \\ @default_language) do
    quote do
      fragment(
        "
        CASE
            WHEN trim(websearch_to_tsquery(?, ?)::text) = '' THEN FALSE
            ELSE to_tsvector(?, ?) @@ (websearch_to_tsquery(?, ?)::text || ':*')::tsquery
        END
        ",
        unquote(language),
        unquote(query_text),
        unquote(language),
        unquote(column),
        unquote(language),
        unquote(query_text)
      )
    end
  end

  defp language(args) do
    args |> Keyword.get(:language, @default_language) |> then(&("'" <> &1 <> "'"))
  end
end
