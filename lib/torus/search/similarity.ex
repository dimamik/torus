defmodule Torus.Search.Similarity do
  @moduledoc false
  import Torus.Search.Common

  @order_types ~w[asc desc none]a
  @similarity_types ~w[word_similarity similarity strict_word_similarity]a
  @true_false ~w[true false]a

  def similarity(query, bindings, qualifiers, term, opts \\ []) do
    # Arguments fetching
    order = get_arg!(opts, :order, :desc, @order_types)
    pre_filter = get_arg!(opts, :pre_filter, false, @true_false)
    qualifiers = List.wrap(qualifiers)
    similarity_type = get_arg!(opts, :type, :word_similarity, @similarity_types)

    # Arguments preparation
    {similarity_function, similarity_operator} =
      case similarity_type do
        :word_similarity -> {"word_similarity", "<%"}
        :similarity -> {"similarity", "%"}
        :strict_word_similarity -> {"strict_word_similarity", "<<%"}
      end

    desc_asc_string = parse_order(order)
    similarity_function = "#{similarity_function}(?, ?) #{desc_asc_string}"
    multiple_qualifiers = length(qualifiers) > 1

    # Query building
    quote do
      unquote(query)
      |> apply_if(unquote(pre_filter) and unquote(multiple_qualifiers), fn query ->
        where(
          query,
          [unquote_splicing(bindings)],
          operator(^unquote(term), unquote(similarity_operator), concat_ws(unquote(qualifiers)))
        )
      end)
      |> apply_if(unquote(pre_filter) and not unquote(multiple_qualifiers), fn query ->
        where(
          query,
          [unquote_splicing(bindings)],
          operator(^unquote(term), unquote(similarity_operator), unquote(List.first(qualifiers)))
        )
      end)
      |> apply_if(unquote(order) != :none and unquote(multiple_qualifiers), fn query ->
        order_by(
          query,
          [unquote_splicing(bindings)],
          fragment(unquote(similarity_function), ^unquote(term), concat_ws(unquote(qualifiers)))
        )
      end)
      |> apply_if(unquote(order) != :none and not unquote(multiple_qualifiers), fn query ->
        order_by(
          query,
          [unquote_splicing(bindings)],
          fragment(unquote(similarity_function), ^unquote(term), unquote(List.first(qualifiers)))
        )
      end)
    end
  end
end
