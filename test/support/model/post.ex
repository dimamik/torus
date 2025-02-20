defmodule TorusTest.Post do
  @moduledoc false
  use Ecto.Schema

  schema "posts" do
    field :title, :string
    field :body, :string
    belongs_to :author, TorusTest.Author
  end
end
