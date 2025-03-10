defmodule Torus.FullTextTest do
  @moduledoc false
  use Torus.Case, async: true

  describe "full_text_dynamic/5 - language" do
    test ":language - defaults to `\"english\"`" do
      insert_post!(title: "magic's most wanted witches")

      sql =
        "SELECT p0.\"title\" FROM \"posts\" AS p0 WHERE (CASE\n    WHEN trim(websearch_to_tsquery('english', 'magic')::text) = '' THEN FALSE\n    ELSE to_tsvector('english', p0.\"title\") @@ (websearch_to_tsquery('english', 'magic')::text || ':*')::tsquery\nEND\n OR 'false') ORDER BY (CASE\n    WHEN trim(websearch_to_tsquery('english', 'magic')::text) = '' THEN 1\n    ELSE ts_rank_cd(setweight(to_tsvector('english', p0.\"title\"), 'A'), (websearch_to_tsquery('english', 'magic')::text || ':*')::tsquery, 4)\nEND) DESC\n"

      assert ^sql =
               Post
               |> Torus.full_text_dynamic([p], p.title, "magic")
               |> select([p], p.title)
               |> QueryInspector.substituted_sql()

      assert ^sql =
               Post
               |> Torus.full_text_dynamic([p], p.title, "magic", language: "english")
               |> select([p], p.title)
               |> QueryInspector.substituted_sql()

      assert "magic's most wanted witches" =
               Post
               |> Torus.full_text_dynamic([p], p.title, "magic")
               |> select([p], p.title)
               |> Repo.one!()
    end

    test ":language - accepts other languages" do
      insert_post!(title: "magiens mest eftersøgte hekse")

      sql =
        "SELECT p0.\"title\" FROM \"posts\" AS p0 WHERE (CASE\n    WHEN trim(websearch_to_tsquery('danish', 'magien')::text) = '' THEN FALSE\n    ELSE to_tsvector('danish', p0.\"title\") @@ (websearch_to_tsquery('danish', 'magien')::text || ':*')::tsquery\nEND\n OR 'false') ORDER BY (CASE\n    WHEN trim(websearch_to_tsquery('danish', 'magien')::text) = '' THEN 1\n    ELSE ts_rank_cd(setweight(to_tsvector('danish', p0.\"title\"), 'A'), (websearch_to_tsquery('danish', 'magien')::text || ':*')::tsquery, 4)\nEND) DESC\n"

      assert ^sql =
               Post
               |> Torus.full_text_dynamic([p], p.title, "magien", language: "danish")
               |> select([p], p.title)
               |> QueryInspector.substituted_sql()

      assert "magiens mest eftersøgte hekse" =
               Post
               |> Torus.full_text_dynamic([p], p.title, "magien", language: "danish")
               |> select([p], p.title)
               |> Repo.one!()
    end
  end

  describe "full_text_dynamic/5 - filter_type" do
    test ":filter_type - defaults to `or`" do
      insert_post!(title: "magic is real")
      insert_post!(body: "hogwarts magic is in our hearts")

      sql =
        "SELECT p0.\"title\" FROM \"posts\" AS p0 WHERE (CASE\n    WHEN trim(websearch_to_tsquery('english', 'magic')::text) = '' THEN FALSE\n    ELSE to_tsvector('english', p0.\"body\") @@ (websearch_to_tsquery('english', 'magic')::text || ':*')::tsquery\nEND\n OR (CASE\n    WHEN trim(websearch_to_tsquery('english', 'magic')::text) = '' THEN FALSE\n    ELSE to_tsvector('english', p0.\"title\") @@ (websearch_to_tsquery('english', 'magic')::text || ':*')::tsquery\nEND\n OR 'false')) ORDER BY (CASE\n    WHEN trim(websearch_to_tsquery('english', 'magic')::text) = '' THEN 1\n    ELSE ts_rank_cd(setweight(to_tsvector('english', p0.\"title\"), 'A') || setweight(to_tsvector('english', p0.\"body\"), 'B'), (websearch_to_tsquery('english', 'magic')::text || ':*')::tsquery, 4)\nEND) DESC\n"

      assert ^sql =
               Post
               |> Torus.full_text_dynamic([p], [p.title, p.body], "magic")
               |> select([p], p.title)
               |> QueryInspector.substituted_sql()

      assert ^sql =
               Post
               |> Torus.full_text_dynamic([p], [p.title, p.body], "magic", filter_type: :or)
               |> select([p], p.title)
               |> QueryInspector.substituted_sql()

      assert ["magic is real", nil] =
               Post
               |> Torus.full_text_dynamic([p], [p.title, p.body], "magic")
               |> select([p], p.title)
               |> Repo.all()
    end

    test ":filter_type - `:concat`" do
      insert_post!(title: "magic is real")
      insert_post!(title: "Dumbledore!", body: "hogwarts magic is in our hearts")

      sql =
        "SELECT p0.\"title\" FROM \"posts\" AS p0 WHERE (CASE\n    WHEN trim(websearch_to_tsquery('english', 'magic')::text) = '' THEN FALSE\n    ELSE setweight(to_tsvector('english', COALESCE(p0.\"title\", '')), 'A') || setweight(to_tsvector('english', COALESCE(p0.\"body\", '')), 'B') @@ (websearch_to_tsquery('english', 'magic')::text || ':*')::tsquery\nEND\n) ORDER BY (CASE\n    WHEN trim(websearch_to_tsquery('english', 'magic')::text) = '' THEN 1\n    ELSE ts_rank_cd(setweight(to_tsvector('english', COALESCE(p0.\"title\", '')), 'A') || setweight(to_tsvector('english', COALESCE(p0.\"body\", '')), 'B'), (websearch_to_tsquery('english', 'magic')::text || ':*')::tsquery, 4)\nEND) DESC\n"

      assert ^sql =
               Post
               |> Torus.full_text_dynamic([p], [p.title, p.body], "magic", filter_type: :concat)
               |> select([p], p.title)
               |> QueryInspector.substituted_sql()

      assert ["magic is real", "Dumbledore!"] =
               Post
               |> Torus.full_text_dynamic([p], [p.title, p.body], "magic", filter_type: :concat)
               |> select([p], p.title)
               |> Repo.all()
    end

    test ":filter_type - `:concat` with an empty term" do
      assert [] =
               Post
               |> Torus.full_text_dynamic([p], [p.title, p.body], "", filter_type: :concat)
               |> select([p], p.title)
               |> Repo.all()
    end

    test ":filter_type - `:none`" do
      insert_post!(title: "magic is real")
      insert_post!(title: "Dumbledore!", body: "hogwarts magic is in our hearts")

      sql =
        "SELECT p0.\"title\" FROM \"posts\" AS p0 ORDER BY (CASE\n    WHEN trim(websearch_to_tsquery('english', 'magic')::text) = '' THEN 1\n    ELSE ts_rank_cd(setweight(to_tsvector('english', p0.\"title\"), 'A') || setweight(to_tsvector('english', p0.\"body\"), 'B'), (websearch_to_tsquery('english', 'magic')::text || ':*')::tsquery, 4)\nEND) DESC\n"

      assert ^sql =
               Post
               |> Torus.full_text_dynamic([p], [p.title, p.body], "magic", filter_type: :none)
               |> select([p], p.title)
               |> QueryInspector.substituted_sql()

      assert ["magic is real", "Dumbledore!"] =
               Post
               |> Torus.full_text_dynamic([p], [p.title, p.body], "magic", filter_type: :none)
               |> select([p], p.title)
               |> Repo.all()
    end
  end

  describe "full_text_dynamic/5 - mixed" do
    test "complex prefix-search" do
      insert_post!(title: "magic is real")
      insert_post!(title: "Dumbledore!", body: "hogwarts magic is in our hearts")

      sql =
        "SELECT p0.\"title\" FROM \"posts\" AS p0 WHERE (CASE\n    WHEN trim(plainto_tsquery('danish', 'magic')::text) = '' THEN FALSE\n    ELSE setweight(to_tsvector('danish', COALESCE(p0.\"title\", '')), 'B') || setweight(to_tsvector('danish', COALESCE(p0.\"body\", '')), 'B') @@ (plainto_tsquery('danish', 'magic')::text || ':*')::tsquery\nEND\n) ORDER BY (CASE\n    WHEN trim(plainto_tsquery('danish', 'magic')::text) = '' THEN 1\n    ELSE ts_rank(setweight(to_tsvector('danish', COALESCE(p0.\"title\", '')), 'B') || setweight(to_tsvector('danish', COALESCE(p0.\"body\", '')), 'B'), (plainto_tsquery('danish', 'magic')::text || ':*')::tsquery, 12)\nEND) ASC\n"

      assert ^sql =
               Post
               |> Torus.full_text_dynamic([p], [p.title, p.body], "magic",
                 filter_type: :concat,
                 language: "danish",
                 prefix_search: true,
                 term_function: :plainto_tsquery,
                 rank_function: :ts_rank,
                 rank_weights: [:B, :B],
                 rank_normalization: 12,
                 order: :asc
               )
               |> select([p], p.title)
               |> QueryInspector.substituted_sql()
    end

    test "complex non-prefix or search" do
      author_a = insert_author!(name: "J.K. Rowling")
      author_b = insert_author!(name: "Another magician")
      insert_post!(title: "magic is real", author: author_a)

      insert_post!(
        title: "Dumbledore!",
        body: "hogwarts magic is in our hearts",
        author: author_b
      )

      assert ["magic is real", "Dumbledore!"] =
               Post
               |> join(:inner, [p], a in assoc(p, :author))
               |> Torus.full_text_dynamic([p, a], [p.title, p.body, a.name], "magic",
                 filter_type: :or,
                 language: "english",
                 prefix_search: false,
                 term_function: :phraseto_tsquery,
                 rank_function: :ts_rank_cd,
                 rank_weights: [:A, :A, :B],
                 order: :desc
               )
               |> select([p], p.title)
               |> Repo.all()

      sql =
        "SELECT p0.\"title\" FROM \"posts\" AS p0 INNER JOIN \"authors\" AS a1 ON a1.\"id\" = p0.\"author_id\" WHERE (to_tsvector('english', a1.\"name\") @@ (phraseto_tsquery('english', 'magic'))::tsquery OR (to_tsvector('english', p0.\"body\") @@ (phraseto_tsquery('english', 'magic'))::tsquery OR (to_tsvector('english', p0.\"title\") @@ (phraseto_tsquery('english', 'magic'))::tsquery OR 'false'))) ORDER BY ts_rank_cd(setweight(to_tsvector('english', p0.\"title\"), 'A') || setweight(to_tsvector('english', p0.\"body\"), 'A') || setweight(to_tsvector('english', a1.\"name\"), 'B'), (phraseto_tsquery('english', 'magic'))::tsquery, 4) DESC"

      assert ^sql =
               Post
               |> join(:inner, [p], a in assoc(p, :author))
               |> Torus.full_text_dynamic([p, a], [p.title, p.body, a.name], "magic",
                 filter_type: :or,
                 language: "english",
                 prefix_search: false,
                 term_function: :phraseto_tsquery,
                 rank_function: :ts_rank_cd,
                 rank_weights: [:A, :A, :B],
                 order: :desc
               )
               |> select([p], p.title)
               |> QueryInspector.substituted_sql()
    end

    test "complex non-prefix concat search" do
      author_a = insert_author!(name: "J.K. Rowling")
      author_b = insert_author!(name: "Another magician")
      insert_post!(title: "magic is real", author: author_a)

      insert_post!(
        title: "Dumbledore!",
        body: "hogwarts magic is in our hearts",
        author: author_b
      )

      assert ["magic is real", "Dumbledore!"] =
               Post
               |> join(:inner, [p], a in assoc(p, :author))
               |> Torus.full_text_dynamic([p, a], [p.title, p.body, a.name], "magic",
                 filter_type: :concat,
                 language: "english",
                 prefix_search: false,
                 term_function: :phraseto_tsquery,
                 rank_function: :ts_rank_cd,
                 rank_weights: [:A, :A, :B],
                 order: :desc
               )
               |> select([p], p.title)
               |> Repo.all()

      sql =
        "SELECT p0.\"title\" FROM \"posts\" AS p0 INNER JOIN \"authors\" AS a1 ON a1.\"id\" = p0.\"author_id\" WHERE (setweight(to_tsvector('english', COALESCE(p0.\"title\", '')), 'A') || setweight(to_tsvector('english', COALESCE(p0.\"body\", '')), 'A') || setweight(to_tsvector('english', COALESCE(a1.\"name\", '')), 'B') @@ (phraseto_tsquery('english', 'magic'))::tsquery) ORDER BY ts_rank_cd(setweight(to_tsvector('english', COALESCE(p0.\"title\", '')), 'A') || setweight(to_tsvector('english', COALESCE(p0.\"body\", '')), 'A') || setweight(to_tsvector('english', COALESCE(a1.\"name\", '')), 'B'), (phraseto_tsquery('english', 'magic'))::tsquery, 4) DESC"

      assert ^sql =
               Post
               |> join(:inner, [p], a in assoc(p, :author))
               |> Torus.full_text_dynamic([p, a], [p.title, p.body, a.name], "magic",
                 filter_type: :concat,
                 language: "english",
                 prefix_search: false,
                 term_function: :phraseto_tsquery,
                 rank_function: :ts_rank_cd,
                 rank_weights: [:A, :A, :B],
                 order: :desc
               )
               |> select([p], p.title)
               |> QueryInspector.substituted_sql()
    end
  end
end
