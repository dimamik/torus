defmodule Torus.Search.Common do
  @moduledoc false

  @order_types ~w[asc desc none]a
  @default_language "english"

  def raise_if(condition, message) do
    if condition, do: raise(message)
  end

  def get_language(opts) do
    opts |> Keyword.get(:language, @default_language) |> then(&("'" <> &1 <> "'"))
  end

  def get_arg!(opts, value_key, value_default, supported_values) do
    value = Keyword.get(opts, value_key, value_default)

    raise_if(
      value not in supported_values,
      "The value of `#{value_key}` should be one of the: #{inspect(supported_values)}"
    )

    value
  end

  def parse_order(order) when order in @order_types do
    order |> to_string() |> String.upcase()
  end

  @doc false
  def apply_if(query, condition, query_fun) do
    if condition, do: query_fun.(query), else: query
  end

  @doc false
  def apply_case(query, case_condition, query_fun) do
    query_fun.(case_condition, query)
  end
end
