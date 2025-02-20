defmodule TorusTest do
  @moduledoc false
  use Torus.Case, async: true
  doctest Torus, import: true

  describe "substring/3" do
    test "correctly extracts substring" do
      insert_post!(title: "foobar")

      assert "oob" =
               Post
               |> select([p], substring(p.title, "%#\"o_b#\"%", "#"))
               |> Repo.one!()
    end
  end
end
