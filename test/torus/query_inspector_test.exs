defmodule Torus.QueryInspectorTest do
  use Torus.Case, async: true

  alias Torus.Test.Repo

  test "substituted_sql/2 - default" do
    assert "SELECT p0.\"id\", p0.\"title\", p0.\"body\", p0.\"author_id\" FROM \"posts\" AS p0 WHERE (p0.\"id\" = 1)" =
             Post |> where(id: 1) |> Torus.QueryInspector.substituted_sql(Repo)
  end

  test "substituted_sql/2 - complex substitution" do
    int_array = [1, 2]
    binary_array = ["hello", "world"]

    assert "SELECT p0.\"id\", p0.\"title\", p0.\"body\", p0.\"author_id\" FROM \"posts\" AS p0 WHERE (p0.\"id\" = ANY(ARRAY[1,2])) AND (p0.\"title\" = ANY(ARRAY['hello','world'])) AND ((p0.\"title\" ILIKE 'test%') OR 'false')" =
             Post
             |> where([p], p.id in ^int_array)
             |> where([p], p.title in ^binary_array)
             |> Torus.ilike([p], p.title, "test%")
             |> Torus.QueryInspector.substituted_sql(Repo)
  end

  test "explain_analyze/2 - default" do
    assert result =
             Post |> where(id: 1) |> Torus.QueryInspector.explain_analyze(Repo)

    assert result =~ "Execution Time"
  end
end
