defmodule Torus.Search.Semantic do
  @moduledoc false
  import Torus.Search.Common

  @distance_types ~w[l2_distance max_inner_product cosine_distance l1_distance hamming_distance jaccard_distance]a

  @vector_operators_map %{
    l2_distance: "<->",
    max_inner_product: "<#>",
    cosine_distance: "<=>",
    l1_distance: "<+>",
    hamming_distance: "<~>",
    jaccard_distance: "<%>"
  }

  @order_types ~w[asc desc none]a

  def semantic(query, bindings, qualifier, vector_term, opts \\ []) do
    # Arguments fetching
    distance = get_arg!(opts, :distance, :l2_distance, @distance_types)
    order = get_arg!(opts, :order, :asc, @order_types)
    operator = Map.fetch!(@vector_operators_map, distance)
    pre_filter = Keyword.get(opts, :pre_filter, :none)

    # Query building
    quote do
      if not is_struct(unquote(vector_term), Pgvector) do
        raise """
        `vector_term` should be a Pgvector struct.

        The best way to generate it is to use `Torus.to_vector/1,2` or `Torus.to_vectors/1,2` functions.
        """
      end

      unquote(query)
      |> apply_if(
        is_float(unquote(pre_filter)),
        fn query ->
          where(
            query,
            [unquote_splicing(bindings)],
            operator(unquote(qualifier), unquote(operator), ^unquote(vector_term)) <
              unquote(pre_filter)
          )
        end
      )
      |> apply_if(unquote(order) != :none, fn query ->
        order_by(
          query,
          [unquote_splicing(bindings)],
          {unquote(order), operator(unquote(qualifier), unquote(operator), ^unquote(vector_term))}
        )
      end)
    end
  end

  def to_vectors(terms, opts \\ []) do
    embedding_module =
      if opts[:embedding_module] do
        opts[:embedding_module]
      else
        Application.fetch_env!(:torus, :embedding_module)
      end

    terms = List.wrap(terms)

    if Code.ensure_loaded?(embedding_module) &&
         function_exported?(embedding_module, :generate, 2) do
      embedding_module.generate(terms, opts)
    else
      raise "`embedding_module` must implement the `Torus.Embedding` behaviour"
    end
  end

  def to_vector(term, opts \\ []) do
    term |> to_vectors(opts) |> List.first()
  end

  def embedding_model(opts \\ []) do
    embedding_module =
      if opts[:embedding_module] do
        opts[:embedding_module]
      else
        Application.fetch_env!(:torus, :embedding_module)
      end

    if Code.ensure_loaded?(embedding_module) &&
         function_exported?(embedding_module, :embedding_model, 1) do
      embedding_module.embedding_model(opts)
    else
      raise "`embedding_module` must implement the `Torus.Embedding` behaviour"
    end
  end
end
