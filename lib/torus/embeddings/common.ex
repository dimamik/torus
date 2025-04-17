defmodule Torus.Embeddings.Common do
  @moduledoc false

  @doc """
  Retrieves an option from the given options or application environment.
  """
  @spec get_option(Keyword.t(), module(), atom() | String.t(), any()) :: any()
  def get_option(opts \\ [], caller_module, key, default \\ nil) do
    opts[key] || Application.get_env(:torus, caller_module)[key] || default
  end

  @doc """
  Same as `get_option/4`, but raises an error if the option is not found.
  """
  @spec get_option!(Keyword.t(), module(), atom() | String.t()) :: any()
  def get_option!(opts \\ [], caller_module, key) do
    get_option(opts, caller_module, key) ||
      raise """
      `#{inspect(key)}` option is required for #{inspect(caller_module)}.
      """
  end
end
