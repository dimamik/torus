defmodule Torus.Test.Repo.Migrations.AddPostEmbeddings do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS vector", "DROP EXTENSION IF EXISTS vector"

    alter table(:posts) do
      add :embedding, :vector, size: 3
    end
  end
end
