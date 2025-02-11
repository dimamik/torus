defmodule Torus.Test.Repo do
  @moduledoc false

  use Ecto.Repo, otp_app: :torus, adapter: Ecto.Adapters.Postgres
end
