defmodule Torus.Int8Range do
  @moduledoc """
  Wraps a `Postgrex.Range` and casts to a PostgreSQL `int8range` type.
  """
  use Torus.Ranges

  @type t :: %__MODULE__{
          lower: integer(),
          lower_inclusive: boolean(),
          upper: integer(),
          upper_inclusive: boolean()
        }

  @doc false
  @spec type() :: :int8range
  def type, do: :int8range
end
