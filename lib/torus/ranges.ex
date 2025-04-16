defmodule Torus.Ranges do
  @moduledoc """
  TODO: Remove
  This module is almost 1-1 copy of `PgRanges` from [pg_ranges](https://github.com/vforgione/pg_ranges/tree/main) library.
  """

  @callback new(lower :: any, upper :: any) :: any
  @callback new(any, any, any) :: any
  @callback from_postgrex(any) :: any
  @callback to_postgrex(any) :: any

  @optional_callbacks new: 2,
                      new: 3,
                      from_postgrex: 1,
                      to_postgrex: 1

  @doc false
  defmacro __using__(opts) do
    quote location: :keep, bind_quoted: [opts: opts] do
      alias Postgrex.Range

      use Ecto.Type
      @behaviour Torus.Ranges
      @before_compile Torus.Ranges

      defstruct lower: nil,
                lower_inclusive: true,
                upper: nil,
                upper_inclusive: false

      @spec new(any, any, keyword()) :: __MODULE__.t()
      def new(lower, upper, opts \\ []) do
        fields = Keyword.merge(opts, lower: lower, upper: upper)
        struct!(__MODULE__, fields)
      end

      @doc false
      @spec from_postgrex(Range.t()) :: __MODULE__.t()
      def from_postgrex(%Range{} = range), do: struct!(__MODULE__, Map.from_struct(range))

      @doc false
      @spec to_postgrex(__MODULE__.t()) :: Range.t()
      def to_postgrex(%__MODULE__{} = range), do: struct!(Range, Map.from_struct(range))

      @doc false
      def cast(nil), do: {:ok, nil}
      def cast(%Range{} = range), do: {:ok, from_postgrex(range)}
      def cast(%__MODULE__{} = range), do: {:ok, range}
      def cast(_), do: :error

      @doc false
      def load(nil), do: {:ok, nil}
      def load(%Range{} = range), do: {:ok, from_postgrex(range)}
      def load(_), do: :error

      @doc false
      def dump(nil), do: {:ok, nil}
      def dump(%__MODULE__{} = range), do: {:ok, to_postgrex(range)}
      def dump(_), do: :error

      defoverridable new: 2,
                     new: 3,
                     from_postgrex: 1,
                     to_postgrex: 1
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    unless Module.defines?(env.module, {:type, 0}) do
      message = """
      function type/0 required by behaviour Ecto.Type is not implemented \
      (in module #{inspect(env.module)}).
      """

      IO.warn(message, Macro.Env.stacktrace(env))

      quote do
        @doc false
        def type, do: :not_a_valid_type
      end
    end
  end
end
