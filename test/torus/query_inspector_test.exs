defmodule Torus.QueryInspectorTest do
  use Torus.Case, async: true

  test "substituted_sql/2 - default" do
    assert "SELECT p0.\"id\", p0.\"title\", p0.\"body\", p0.\"author_id\" FROM \"posts\" AS p0 WHERE (p0.\"id\" = 1)" =
             Post |> where(id: 1) |> Torus.QueryInspector.substituted_sql(Torus.Test.Repo)
  end

  test "substituted_sql/2 - complex substitution" do
    assert "SELECT p0.\"id\", p0.\"title\", p0.\"body\", p0.\"author_id\" FROM \"posts\" AS p0 WHERE (p0.\"id\" = 1) AND (p0.\"title\" IN ('hello','world'))" =
             Post
             |> where(id: 1)
             |> where([p], p.title in ~w(hello world))
             |> Torus.QueryInspector.substituted_sql(Torus.Test.Repo)
  end
end
