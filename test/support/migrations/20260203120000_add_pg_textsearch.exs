defmodule Torus.Test.Repo.Migrations.AddPgTextsearch do
  use Ecto.Migration

  def up do
    execute "CREATE EXTENSION IF NOT EXISTS pg_textsearch"

    execute """
    CREATE INDEX posts_body_bm25_idx ON posts
    USING bm25(body) WITH (text_config='english')
    """

    execute """
    CREATE INDEX posts_title_bm25_idx ON posts
    USING bm25(title) WITH (text_config='english')
    """
  end

  def down do
    execute "DROP INDEX IF EXISTS posts_body_bm25_idx"
    execute "DROP INDEX IF EXISTS posts_title_bm25_idx"
    execute "DROP EXTENSION IF EXISTS pg_textsearch CASCADE"
  end
end
