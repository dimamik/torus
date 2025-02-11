defmodule Test.Utils do
  alias Torus.Test.Repo

  def insert!(struct) do
    Repo.insert!(struct)
  end

  @doc """
  Returns `true` if `response_list` and `expected_list` contain the same elements,
  regardless of order. Lists may contain nested lists, which are compared recursively.

  ## Examples

      iex> compare_unordered([1, 2, [3, 4]], [[4, 3], 2, 1])
      true

      iex> compare_unordered([1, 2, [3, 5]], [[4, 3], 2, 1])
      false
  """
  def compare_unordered(response_list, expected_list)
      when is_list(response_list) and is_list(expected_list) do
    compare_lists(response_list, expected_list)
  end

  # If both are not lists, just compare them directly.
  def compare_unordered(a, b), do: a == b

  # Recursive helper that attempts to match every element from list1 with an element from list2.
  defp compare_lists([], []), do: true

  defp compare_lists([head | tail], list2) do
    case find_and_remove(head, list2) do
      {:ok, new_list2} ->
        compare_lists(tail, new_list2)

      :error ->
        false
    end
  end

  # If the lists have different lengths, they cannot be equal.
  defp compare_lists(_, _), do: false

  # Try to find an element in `list` that is deeply equal to `elem`.
  # If found, return {:ok, list_without_that_element}.
  defp find_and_remove(elem, list) do
    Enum.reduce_while(list, :error, fn x, _acc ->
      if deep_equal(elem, x) do
        # List.delete/2 deletes only the first occurrence.
        {:halt, {:ok, List.delete(list, x)}}
      else
        {:cont, :error}
      end
    end)
  end

  # Deeply compare two values. If both are lists, use `compare_unordered/2` for recursive comparison.
  defp deep_equal(a, b) when is_list(a) and is_list(b) do
    compare_unordered(a, b)
  end

  # Otherwise, use direct equality.
  defp deep_equal(a, b), do: a == b
end
