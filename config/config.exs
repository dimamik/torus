import Config

config :logger, level: :warning

config :torus, Torus.Test.Repo,
  migration_lock: false,
  pool_size: System.schedulers_online() * 2,
  pool: Ecto.Adapters.SQL.Sandbox,
  types: Torus.Test.PostgrexTypes,
  priv: "test/support",
  show_sensitive_data_on_connection_error: true,
  stacktrace: true,
  url: System.get_env("POSTGRES_URL") || "postgres://localhost:5432/torus_test"

config :torus, ecto_repos: [Torus.Test.Repo]

config :torus, batcher: Torus.Embeddings.Batcher

config :torus, Torus.Embeddings.Batcher,
  max_batch_size: 10,
  default_batch_timeout: 100,
  embedding_module: Torus.Embeddings.HuggingFace

if Mix.env() == :test do
  import_config "#{config_env()}.exs"
end
