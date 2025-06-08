defmodule Torus.Search.FullText do
  @moduledoc false
  import Torus.Search.Common

  @supported_weights ~w[A B C D]
  @term_functions ~w[websearch_to_tsquery plainto_tsquery phraseto_tsquery]a
  @rank_functions ~w[ts_rank_cd ts_rank]a
  @filter_types ~w[or concat none]a
  @true_false ~w[true false]a
  @order_types ~w[desc asc none]a

  def full_text(query, bindings, qualifiers, term, opts \\ []) do
    # Arguments fetching
    qualifiers = List.wrap(qualifiers)
    language = get_language(opts)
    prefix_search = get_arg!(opts, :prefix_search, true, @true_false)
    empty_return = get_arg!(opts, :empty_return, true, @true_false)
    stored = get_arg!(opts, :stored, false, @true_false)
    term_function = get_arg!(opts, :term_function, :websearch_to_tsquery, @term_functions)
    rank_function = get_arg!(opts, :rank_function, :ts_rank_cd, @rank_functions)
    filter_type = get_arg!(opts, :filter_type, :or, @filter_types)
    order = get_arg!(opts, :order, :desc, @order_types)

    rank_weights =
      Keyword.get_lazy(opts, :rank_weights, fn ->
        exceeding_size = max(length(qualifiers) - 4, 0)
        [:A, :B, :C, :D] ++ List.duplicate(:D, exceeding_size)
      end)

    rank_normalization =
      Keyword.get_lazy(opts, :rank_normalization, fn ->
        if rank_function == :ts_rank_cd, do: 4, else: 1
      end)

    coalesce = Keyword.get(opts, :coalesce, filter_type == :concat and length(qualifiers) > 1)
    coalesce = coalesce and filter_type == :concat and length(qualifiers) > 1
    empty_return = empty_return |> to_string() |> String.upcase()

    # Arguments validation
    raise_if(
      length(rank_weights) < length(qualifiers),
      "The length of `rank_weights` should be the same as the length of the qualifiers."
    )

    raise_if(
      not Enum.all?(rank_weights, &(to_string(&1) in @supported_weights)),
      "Each rank weight from `rank_weights` should be one of the: #{@supported_weights}"
    )

    # Arguments preparation
    prefix_string = prefix_search_string(prefix_search)
    desc_asc = parse_order(order)

    weighted_columns = prepare_weights(qualifiers, stored, language, rank_weights, coalesce)

    concat_filter_string =
      "#{weighted_columns} @@ (#{term_function}(#{language}, ?)#{prefix_string})::tsquery"

    concat_filter_fragment =
      if prefix_search do
        # We need to handle empty strings for prefix search queries
        concat_filter_string = """
        CASE
            WHEN trim(#{term_function}(#{language}, ?)::text) = '' THEN #{empty_return}
            ELSE #{concat_filter_string}
        END
        """

        quote do
          fragment(
            unquote(concat_filter_string),
            ^unquote(term),
            unquote_splicing(qualifiers),
            ^unquote(term)
          )
        end
      else
        quote do
          fragment(
            unquote(concat_filter_string),
            unquote_splicing(qualifiers),
            ^unquote(term)
          )
        end
      end

    order_string =
      "#{rank_function}(#{weighted_columns}, (#{term_function}(#{language}, ?)#{prefix_string})::tsquery, #{rank_normalization})"

    order_fragment =
      if prefix_search do
        # We need to handle empty strings for prefix search queries
        order_string = """
        (CASE
            WHEN trim(#{term_function}(#{language}, ?)::text) = '' THEN 1
            ELSE #{order_string}
        END) #{desc_asc}
        """

        quote do
          fragment(
            unquote(order_string),
            ^unquote(term),
            unquote_splicing(qualifiers),
            ^unquote(term)
          )
        end
      else
        order_string = "#{order_string} #{desc_asc}"

        quote do
          fragment(unquote(order_string), unquote_splicing(qualifiers), ^unquote(term))
        end
      end

    or_filter_ast =
      Enum.reduce(qualifiers, false, fn qualifier, conditions_acc ->
        quote do
          dynamic(
            [unquote_splicing(bindings)],
            to_tsquery(unquote(qualifier), ^unquote(term), unquote(opts)) or
              ^unquote(conditions_acc)
          )
        end
      end)

    # Query building
    quote do
      unquote(query)
      |> apply_case(
        unquote(filter_type),
        fn
          :none, query ->
            query

          :or, query ->
            where(unquote(query), ^unquote(or_filter_ast))

          :concat, query ->
            where(unquote(query), [unquote_splicing(bindings)], unquote(concat_filter_fragment))
        end
      )
      |> apply_if(unquote(order) != :none, fn query ->
        order_by(query, [unquote_splicing(bindings)], unquote(order_fragment))
      end)
    end
  end

  def to_tsquery(column, query_text, opts) do
    language = get_language(opts)
    prefix_search = get_arg!(opts, :prefix_search, true, @true_false)
    empty_return = get_arg!(opts, :empty_return, true, @true_false)
    stored = get_arg!(opts, :stored, false, @true_false)
    prefix_string = prefix_search_string(prefix_search)
    term_function = get_arg!(opts, :term_function, :websearch_to_tsquery, @term_functions)
    vector = if stored, do: "?", else: "to_tsvector(#{language}, ?)"
    empty_return = empty_return |> to_string() |> String.upcase()

    ts_vector_match_string =
      "#{vector} @@ (#{term_function}(#{language}, ?)#{prefix_string})::tsquery"

    if prefix_search do
      ts_vector_match_string = """
      CASE
          WHEN trim(#{term_function}(#{language}, ?)::text) = '' THEN #{empty_return}
          ELSE #{ts_vector_match_string}
      END
      """

      quote do
        fragment(
          unquote(ts_vector_match_string),
          unquote(query_text),
          unquote(column),
          unquote(query_text)
        )
      end
    else
      quote do
        fragment(
          unquote(ts_vector_match_string),
          unquote(column),
          unquote(query_text)
        )
      end
    end
  end

  defp prepare_weights(qualifiers, false, language, rank_weights, coalesce) do
    qualifiers
    |> Enum.with_index()
    |> Enum.map_join(" || ", fn {_qualifier, index} ->
      weight = Enum.fetch!(rank_weights, index)
      coalesce = if coalesce, do: "COALESCE(?, '')", else: "?"
      "setweight(to_tsvector(#{language}, #{coalesce}), '#{weight}')"
    end)
  end

  defp prepare_weights(qualifiers, true, _language, rank_weights, coalesce) do
    qualifiers
    |> Enum.with_index()
    |> Enum.map_join(" || ", fn {_qualifier, index} ->
      weight = Enum.fetch!(rank_weights, index)
      coalesce = if coalesce, do: "COALESCE(?, '')", else: "?"
      "setweight(#{coalesce}, '#{weight}')"
    end)
  end

  defp prefix_search_string(prefix_search) when is_boolean(prefix_search) do
    if prefix_search, do: "::text || ':*'", else: ""
  end
end
