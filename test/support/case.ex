defmodule Torus.Case do
  @moduledoc false
  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox
  alias Torus.Test.Repo

  setup context do
    pid = Sandbox.start_owner!(Repo, shared: not context[:async])

    on_exit(fn -> Sandbox.stop_owner(pid) end)

    :ok
  end

  using do
    quote do
      import Torus
      import Ecto.Query

      alias Torus.Test.Repo
      alias TorusTest.Author
      alias TorusTest.Post

      def insert_post!(args) do
        insert!(Post, args)
      end

      def insert_author!(args) do
        insert!(Author, args)
      end

      defp insert!(schema, args) do
        args
        |> Keyword.to_list()
        |> :maps.from_list()
        |> then(&struct(schema, &1))
        |> Repo.insert!()
      end
    end
  end
end
