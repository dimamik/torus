defmodule Torus.PatternMatchTest do
  use Torus.Case, async: true

  describe "sanitize/1" do
    test "correctly escapes special characters from a string" do
      assert "foo" = Torus.sanitize("%foo%")
      assert "foo" = Torus.sanitize("_foo_")
      assert "foo" = Torus.sanitize("_foo\\")
      assert "foobar" = Torus.sanitize("_foo\\bar")
      assert "foo|bar" = Torus.sanitize("_foo|bar")
    end
  end

  describe "ilike/5" do
    test "finds case-insensitive matches across multiple columns" do
      insert_post!(title: "The Hogwarts", body: "Complete chronicle of the castle")
      insert_post!(title: "hogwarts express", body: "Train to magical education")

      assert ["The Hogwarts", "hogwarts express"] =
               Post
               |> Torus.ilike([p], p.title, "%hogwarts%")
               |> select([p], p.title)
               |> order_by([p], p.id)
               |> Repo.all()
    end
  end

  describe "like/5" do
    test "finds case-sensitive matches across multiple columns" do
      insert_post!(title: "The Hogwarts", body: "Complete chronicle of the castle")
      insert_post!(title: "hogwarts express", body: "Train to magical education")

      assert ["hogwarts express"] =
               Post
               |> Torus.like([p], p.title, "%hogwarts%")
               |> select([p], p.title)
               |> order_by([p], p.id)
               |> Repo.all()
    end
  end

  describe "similar_to/5" do
    test "correctly matches SQL SIMILAR TO behaviour" do
      insert_post!(title: "Gryffindor", body: "Brave at heart")
      insert_post!(title: "Hufflepuff", body: "Just and loyal")
      insert_post!(title: "Ravenclaw", body: "Wit and learning")
      insert_post!(title: "Slytherin", body: "Cunning and ambitious")

      # Test pattern matching any titles with 'r' or 'R'
      assert ["Gryffindor", "Ravenclaw", "Slytherin"] =
               Post
               |> Torus.similar_to([p], p.title, "%(r|R)%")
               |> select([p], p.title)
               |> Repo.all()
               |> Enum.sort()

      # Test exact house name matching
      assert ["Gryffindor", "Ravenclaw"] =
               Post
               |> Torus.similar_to([p], p.title, "%(Gryffindor|Ravenclaw)%")
               |> select([p], p.title)
               |> Repo.all()
               |> Enum.sort()
    end

    test "correctly handles complex regex-like expressions" do
      insert_post!(title: "Spell-123-Lumos", body: "Light spell")
      insert_post!(title: "Incantation12345", body: "Basic charm")
      insert_post!(title: "123Alohomora", body: "Unlocking charm")
      insert_post!(title: "Accio123", body: "Summoning charm")

      expression = "%([-][0-9]+)+%"

      assert ["Spell-123-Lumos"] =
               Post
               |> Torus.similar_to([p], [p.title, p.body], expression)
               |> select([p], p.title)
               |> Repo.all()
    end
  end

  describe "substring/3" do
    test "correctly extracts substrings" do
      insert_post!(title: "Spell718Stupefy", body: "Stunning spell")
      insert_post!(title: "456Expelliarmus", body: "Disarming charm")
      insert_post!(title: "No spell number", body: "Basic charm")

      assert [nil, "456", "718"] =
               Post
               |> where([p], not is_nil(p.title))
               |> select([p], substring(p.title, "%#\"[0-9]+#\"%", "#"))
               |> Repo.all()
               |> Enum.sort()
    end
  end
end
