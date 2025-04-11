defmodule Torus.QueryInspector do
  @moduledoc """
  Helpers to debug your SQL queries. You can this module both while creating the
  queries and directly in your running production shell once deployed, so that the
  explain analyze returns more accurate results.
  """

  alias Ecto.{Repo, Query}

  @doc """
  Converts the query to SQL and prints it to the console. Returns the query.
  """
  @spec tap_sql(Query.t(), Repo.t(), :all | :update_all | :delete_all) :: Query.t()
  def tap_sql(query, repo, kind \\ :all) do
    kind
    |> Ecto.Adapters.SQL.to_sql(repo, query)
    |> IO.puts()

    query
  end

  @doc """
  Runs explain analyze on the query and prints it to the console. Returns the query.

  **Runs the query!**
  """
  @spec tap_explain_analyze(Query.t(), Repo.t(), :all | :update_all | :delete_all) ::
          Query.t()
  def tap_explain_analyze(query, repo, kind \\ :all) do
    tap(query, &(Ecto.Adapters.SQL.explain(repo, kind, &1, analyze: true) |> IO.puts()))
  end

  @doc """
  Substitutes the parameters in the query and prints the SQL to the console. Returns the query.
  The SQL is in its raw form and can be directly executed by postgres.

  ## Example
      iex> Post
      ...> |> where(id: 1)
      ...> # ... Your complex query
      ...> |> Torus.QueryInspector.tap_substituted_sql(Torus.Test.Repo)
      ...> |> Repo.all()
  """
  def tap_substituted_sql(query, repo, kind \\ :all) do
    query
    |> substituted_sql(repo, kind)
    |> IO.puts()

    query
  end

  @doc """
  Substitutes the params into the SQL.

  ## Examples

      iex> Post |> where(id: 1) |> Torus.QueryInspector.substituted_sql(Torus.Test.Repo)
      "SELECT p0.\"id\", p0.\"title\", p0.\"body\", p0.\"author_id\" FROM \"posts\" AS p0 WHERE (p0.\"id\" = 1)"
  """
  @spec substituted_sql(Query.t(), Repo.t(), :all | :update_all | :delete_all) ::
          String.t()
  def substituted_sql(query, repo, kind \\ :all) do
    {raw_log, params} = Ecto.Adapters.SQL.to_sql(kind, repo, query)

    params
    |> Enum.with_index()
    |> Enum.reverse()
    |> Enum.reduce(raw_log, fn {param, index}, acc ->
      String.replace(acc, "$" <> to_string(index + 1), to_postgres_string(param))
    end)
  end

  defp to_postgres_string(list) when is_list(list) do
    "ARRAY[#{Enum.map_join(list, ",", &to_postgres_string/1)}]"
  end

  defp to_postgres_string(string) do
    "'#{string}'"
  end
end
