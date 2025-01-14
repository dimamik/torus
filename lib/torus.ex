defmodule Torus do
  @moduledoc """
  Generic utility functions for Elixir.
  """

  @doc """
  Recursively replaces the value at the given path with the new value.
  Supports lists, maps, and nested lists and maps.

  ## Example
    ```elixir
    iex> replace_in(%{first_key: [%{second_key: 1}]}, [:first_key, 0, :second_key], 2)
    %{first_key: [%{second_key: 2}]}
    ```
    Or the value can be a function that takes the current value and returns the new value:

    ```elixir
    iex> replace_in([%{first_key: 2}], [0, :first_key], &Kernel.*(&1, 5))
    [%{first_key: 10}]
    ```

  """
  def replace_in(map, [current | [_ | _] = rest], new_value)
      when is_atom(current) or is_binary(current) do
    %{map | current => replace_in(Map.fetch!(map, current), rest, new_value)}
  end

  def replace_in(list, [current | [_ | _] = rest], new_value) when is_integer(current) do
    List.replace_at(list, current, replace_in(Enum.at(list, current), rest, new_value))
  end

  def replace_in(map, [last], update_func)
      when (is_function(update_func) and is_atom(last)) or is_binary(last) do
    %{map | last => update_func.(map[last])}
  end

  def replace_in(map, [last], new_value) when is_atom(last) or is_binary(last) do
    %{map | last => new_value}
  end

  def replace_in(map, [], _new_value), do: map
end
