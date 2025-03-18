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

      add :tsv, :tsvector
    end

    execute """
    CREATE TRIGGER update_title_and_body_vectors BEFORE INSERT OR UPDATE
    ON posts FOR EACH ROW EXECUTE FUNCTION
    tsvector_update_trigger(tsv, 'pg_catalog.english', title, body);
    """

    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm;", ""
  end
end
