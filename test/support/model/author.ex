defmodule TorusTest.Author do
  @moduledoc false
  use Ecto.Schema

  schema "authors" do
    field :name, :string
  end
end
