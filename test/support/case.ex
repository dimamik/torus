defmodule Torus.Case do
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

      def insert_post!(title: title, body: body) do
        Repo.insert!(%Post{title: title, body: body})
      end

      def insert_post!(title: title, body: body, author: author) do
        Repo.insert!(%Post{title: title, body: body, author: author})
      end

      def insert_author!(name: name) do
        Repo.insert!(%Author{name: name})
      end
    end
  end
end
