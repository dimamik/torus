defmodule Torus.FullTextTest do
  @moduledoc false
  use Torus.Case, async: true

  describe "full_text_dynamic/5 - type" do
    test ":type - defaults to `:full_text_dynamic`" do
      insert_post!(title: "hogwarts lives there")

      sql =
        "SELECT p0.\"title\" FROM \"posts\" AS p0 ORDER BY full_text_dynamic('hogwarts', p0.\"title\") DESC"

      assert ^sql =
               Post
               |> Torus.full_text_dynamic([p], p.title, "hogwarts")
               |> select([p], p.title)
               |> QueryInspector.substituted_sql()

      assert ^sql =
               Post
               |> Torus.full_text_dynamic([p], p.title, "hogwarts")
               |> select([p], p.title)
               |> QueryInspector.substituted_sql()

      assert "hogwarts lives there" =
               Post
               |> Torus.full_text_dynamic([p], p.title, "hogwarts")
               |> select([p], p.title)
               |> Repo.one!()
    end
  end
end
