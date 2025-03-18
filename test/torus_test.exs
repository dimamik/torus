defmodule TorusTest do
  @moduledoc false
  use Torus.Case, async: true
  doctest Torus, import: true

  describe "substring/3" do
    test "correctly extracts substring" do
      insert_post!(title: "foobar")
      string = "%#\"o_b#\"%"

      assert "oob" =
               Post
               |> select([p], substring(p.title, string, "#"))
               |> Repo.one!()
    end
  end

  describe "ilike/5" do
    test "correctly pins the term" do
      insert_post!(title: "pinnedThingy")
      term = "PiNnEd%"

      assert ["pinnedThingy"] =
               Post
               |> Torus.ilike([p], p.title, term)
               |> select([p], p.title)
               |> Repo.all()
    end
  end

  describe "like/5" do
    test "correctly pins the term" do
      insert_post!(title: "pinned_thingy")
      term = "pinned%"

      assert ["pinned_thingy"] =
               Post
               |> Torus.like([p], p.title, term)
               |> select([p], p.title)
               |> Repo.all()
    end
  end

  describe "keywords queries" do
    # Other functions would work the same
    test "like/5" do
      insert_post!(title: "pinned_thingy")

      assert ["pinned_thingy"] =
               from(p in Post, select: p.title)
               |> Torus.like([p], p.title, "pinned%")
               |> Repo.all()
    end
  end
end
