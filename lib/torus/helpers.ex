defmodule Torus.Helpers do
  @moduledoc """
  Helpers to debug your SQL queries. You can this module both while creating the
  queries and directly in your running production shell once deployed, so that the
  explain analyze returns more accurate results.
  """

  @doc """
  Converts the query to SQL and prints it to the console. Returns the query.
  """
  @spec tap_sql(Ecto.Query.t(), :all | :update_all | :delete_all, Ecto.Repo) :: Ecto.Query.t()
  def tap_sql(query, kind \\ :all, repo \\ Torus.Test.Repo) do
    # credo:disable-for-next-line  Credo.Check.Warning.IoInspect
    tap(query, &(Ecto.Adapters.SQL.to_sql(kind, repo, &1) |> IO.inspect()))
  end

  @doc """
  Runs explain analyze on the query and prints it to the console. Returns the query.

  **Runs the query!**
  """
  @spec tap_explain_analyze(Ecto.Query.t(), :all | :update_all | :delete_all, Ecto.Repo) ::
          Ecto.Query.t()
  def tap_explain_analyze(query, kind \\ :all, repo \\ Torus.Test.Repo) do
    # credo:disable-for-next-line  Credo.Check.Warning.IoInspect
    tap(query, &(Ecto.Adapters.SQL.explain(repo, kind, &1, :analyze) |> IO.puts()))
  end
end
