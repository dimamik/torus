defmodule Torus.Helpers do
  @moduledoc false
  def tap_to_sql(query, kind \\ :all) do
    # credo:disable-for-next-line  Credo.Check.Warning.IoInspect
    tap(query, &(Ecto.Adapters.SQL.to_sql(kind, Torus.Test.Repo, &1) |> IO.inspect()))
  end
end
