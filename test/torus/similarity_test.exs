defmodule Torus.SimilarityTest do
  @moduledoc false
  use Torus.Case, async: true

  describe "similarity/5 - type" do
    test ":type - defaults to `:similarity`" do
      insert_post!(title: "hogwarts lives there")

      sql =
        "SELECT p0.\"title\" FROM \"posts\" AS p0 ORDER BY similarity('hogwarts', p0.\"title\") DESC"

      assert ^sql =
               Post
               |> Torus.similarity([p], p.title, "hogwarts")
               |> select([p], p.title)
               |> QueryInspector.substituted_sql()

      assert ^sql =
               Post
               |> Torus.similarity([p], p.title, "hogwarts")
               |> select([p], p.title)
               |> QueryInspector.substituted_sql()

      assert "hogwarts lives there" =
               Post
               |> Torus.similarity([p], p.title, "hogwarts")
               |> select([p], p.title)
               |> Repo.one!()
    end

    test ":type - `:strict_similarity`" do
      insert_post!(title: "foobar")

      refute Post
             |> Torus.similarity([p], p.title, "foo", type: :strict, pre_filter: true)
             |> select([p], p.title)
             |> Repo.exists?()

      assert "foobar" =
               Post
               |> Torus.similarity([p], p.title, "foobar", type: :strict, pre_filter: true)
               |> select([p], p.title)
               |> Repo.one!()

      assert "SELECT p0.\"title\" FROM \"posts\" AS p0 WHERE ('foo' <<% p0.\"title\") ORDER BY strict_word_similarity('foo', p0.\"title\") DESC" =
               Post
               |> Torus.similarity([p], p.title, "foo", type: :strict, pre_filter: true)
               |> select([p], p.title)
               |> QueryInspector.substituted_sql()
    end

    test ":type - `:full`" do
      insert_post!(title: "foobar")

      assert "foobar" =
               Post
               |> Torus.similarity([p], p.title, "foo", type: :full)
               |> select([p], p.title)
               |> Repo.one!()

      assert "SELECT p0.\"title\" FROM \"posts\" AS p0 ORDER BY similarity('foo', p0.\"title\") DESC" =
               Post
               |> Torus.similarity([p], p.title, "foo", type: :full)
               |> select([p], p.title)
               |> QueryInspector.substituted_sql()
    end
  end

  describe "similarity/5 - order" do
    test ":order - defaults to `:desc`" do
      insert_post!(title: "foobar")
      insert_post!(title: "foo")

      assert ["foo", "foobar"] =
               Post
               |> Torus.similarity([p], p.title, "foo")
               |> select([p], p.title)
               |> Repo.all()

      assert "SELECT p0.\"title\" FROM \"posts\" AS p0 ORDER BY similarity('foo', p0.\"title\") DESC" =
               Post
               |> Torus.similarity([p], p.title, "foo")
               |> select([p], p.title)
               |> QueryInspector.substituted_sql()

      assert "SELECT p0.\"title\" FROM \"posts\" AS p0 ORDER BY similarity('foo', p0.\"title\") DESC" =
               Post
               |> Torus.similarity([p], p.title, "foo", order: :desc)
               |> select([p], p.title)
               |> QueryInspector.substituted_sql()
    end

    test ":order - `:asc`" do
      insert_post!(title: "foobar")
      insert_post!(title: "foo")

      assert ["foobar", "foo"] =
               Post
               |> Torus.similarity([p], p.title, "foo", order: :asc)
               |> select([p], p.title)
               |> Repo.all()

      assert "SELECT p0.\"title\" FROM \"posts\" AS p0 ORDER BY similarity('foo', p0.\"title\") ASC" =
               Post
               |> Torus.similarity([p], p.title, "foo", order: :asc)
               |> select([p], p.title)
               |> QueryInspector.substituted_sql()
    end

    test ":order - `:none`" do
      insert_post!(title: "foobar")

      assert "foobar" =
               Post
               |> Torus.similarity([p], p.title, "foo", order: :none)
               |> select([p], p.title)
               |> Repo.one!()

      assert "SELECT p0.\"title\" FROM \"posts\" AS p0" =
               Post
               |> Torus.similarity([p], p.title, "foo", order: :none)
               |> select([p], p.title)
               |> QueryInspector.substituted_sql()
    end
  end

  describe "similarity/5 - pre_filter" do
    test ":pre_filter - defaults to `false`" do
      assert "SELECT p0.\"title\" FROM \"posts\" AS p0 ORDER BY similarity('foo', p0.\"title\") DESC" =
               Post
               |> Torus.similarity([p], p.title, "foo")
               |> select([p], p.title)
               |> QueryInspector.substituted_sql()
    end

    test ":pre_filter - `true`" do
      assert "SELECT p0.\"title\" FROM \"posts\" AS p0 WHERE ('foo' % p0.\"title\") ORDER BY similarity('foo', p0.\"title\") DESC" =
               Post
               |> Torus.similarity([p], p.title, "foo", pre_filter: true)
               |> select([p], p.title)
               |> QueryInspector.substituted_sql()
    end
  end

  describe "similarity/5 - multiple columns" do
    test ":join_type - for now always concatenates the strings" do
      insert_post!(title: "Hogwarts Game!", body: "barts")
      insert_post!(title: "another", body: "foo")

      assert "SELECT p0.\"title\" FROM \"posts\" AS p0 ORDER BY similarity('howarts', concat_ws(' ', p0.\"title\", p0.\"body\")) DESC" =
               Post
               |> Torus.similarity([p], [p.title, p.body], "howarts")
               |> select([p], p.title)
               |> QueryInspector.substituted_sql()

      assert "Hogwarts Game!" =
               Post
               |> Torus.similarity([p], [p.title, p.body], "howarts", pre_filter: true)
               |> select([p], p.title)
               |> Repo.one!()
    end
  end

  describe "similarity/5 - null values" do
    test "correctly escapes null values" do
      insert_post!(title: nil, body: "foo")
      insert_post!(title: "foo", body: nil)
      insert_post!(title: nil, body: nil)

      assert "SELECT p0.\"title\" FROM \"posts\" AS p0 ORDER BY similarity('foo', concat_ws(' ', p0.\"title\", p0.\"body\")) DESC" =
               Post
               |> Torus.similarity([p], [p.title, p.body], "foo")
               |> select([p], p.title)
               |> QueryInspector.substituted_sql()

      assert [nil, "foo", nil] =
               Post
               |> Torus.similarity([p], [p.title, p.body], "foo")
               |> select([p], p.title)
               |> Repo.all()
    end
  end

  describe "similarity/5 - variable terms" do
    test "correctly pins variable terms" do
      insert_post!(title: nil, body: "foo")
      insert_post!(title: "foo", body: nil)
      insert_post!(title: nil, body: nil)

      term = "foo"

      assert [nil, "foo", nil] =
               Post
               |> Torus.similarity([p], [p.title, p.body], term)
               |> select([p], p.title)
               |> Repo.all()
    end
  end
end
