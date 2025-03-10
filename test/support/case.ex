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
      import Ecto.Query
      import Torus
      import Torus.TestHelpers

      alias Torus.TestHelpers, as: QueryInspector
      alias Torus.Test.Repo
      alias TorusTest.Author
      alias TorusTest.Post

      def insert_post!(args) do
        insert!(Post, args)
      end

      def insert_posts!(titles: titles) when is_list(titles) do
        for title <- titles do
          insert_post!(title: title)
        end
      end

      def insert_posts!([title | _] = titles) when is_list(titles) and is_binary(title) do
        for title <- titles do
          insert_post!(title: title)
        end
      end

      def insert_posts!([post | _] = posts) when is_map(post) do
        for post <- posts do
          insert_post!(Keyword.new(post))
        end
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
