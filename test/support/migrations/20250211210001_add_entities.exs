defmodule Torus.Test.Repo.Migrations.AddEntities do
  use Ecto.Migration

  def change do
    create table(:authors) do
      add :name, :text
    end

    create table(:posts) do
      add :title, :text
      add :body, :text
      add :author_id, references(:authors)
    end

    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm;", ""
  end
end
