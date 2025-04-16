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
  username: "root",
  url: System.get_env("POSTGRES_URL") || "postgres://localhost:5432/torus_test"

config :torus, ecto_repos: [Torus.Test.Repo]
