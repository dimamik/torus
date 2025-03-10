defmodule Torus.TestHelpers do
  @moduledoc false

  alias Torus.QueryInspector
  alias Torus.Test.Repo

  defdelegate tap_sql(query, repo \\ Repo, kind \\ :all), to: QueryInspector

  defdelegate tap_explain_analyze(query, repo \\ Repo, kind \\ :all), to: QueryInspector

  defdelegate tap_substituted_sql(query, repo \\ Repo, kind \\ :all), to: QueryInspector

  defdelegate substituted_sql(query, repo \\ Repo, kind \\ :all), to: QueryInspector
end
