defmodule Torus.Search.PatternMatch do
  @moduledoc false

  alias Torus.Search.Highlight

  def ilike(query, bindings, qualifiers, term, opts) do
    qualifiers = List.wrap(qualifiers)

    where_ast =
      Enum.reduce(qualifiers, false, fn qualifier, conditions_acc ->
        quote do
          dynamic(
            [unquote_splicing(bindings)],
            ilike(unquote(qualifier), ^unquote(term)) or ^unquote(conditions_acc)
          )
        end
      end)

    query_ast =
      quote do
        where(unquote(query), ^unquote(where_ast))
      end

    Highlight.merge_highlight(query_ast, bindings, sanitized(term), opts, :substring)
  end

  def like(query, bindings, qualifiers, term, opts) do
    qualifiers = List.wrap(qualifiers)

    where_ast =
      Enum.reduce(qualifiers, false, fn qualifier, conditions_acc ->
        quote do
          dynamic(
            [unquote_splicing(bindings)],
            like(unquote(qualifier), ^unquote(term)) or ^unquote(conditions_acc)
          )
        end
      end)

    query_ast =
      quote do
        where(unquote(query), ^unquote(where_ast))
      end

    opts = Keyword.put_new(opts, :case_sensitive, true)
    Highlight.merge_highlight(query_ast, bindings, sanitized(term), opts, :substring)
  end

  defp sanitized(term) do
    quote do
      Torus.sanitize(unquote(term))
    end
  end

  def similar_to(query, bindings, qualifiers, term) do
    qualifiers = List.wrap(qualifiers)

    where_ast =
      Enum.reduce(qualifiers, false, fn qualifier, conditions_acc ->
        quote do
          dynamic(
            [unquote_splicing(bindings)],
            operator(unquote(qualifier), "SIMILAR TO", ^unquote(term)) or ^unquote(conditions_acc)
          )
        end
      end)

    quote do
      where(unquote(query), ^unquote(where_ast))
    end
  end

  def sanitize(term) when is_binary(term) do
    String.replace(term, ~r/[%_\\]/u, "")
  end
end
