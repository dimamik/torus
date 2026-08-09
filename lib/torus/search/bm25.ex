defmodule Torus.Search.BM25 do
  @moduledoc false
  import Torus.Search.Common
  import Ecto.Query, warn: false

  @order_types ~w[asc desc none]a
  @true_false ~w(true false)a

  def bm25(query, bindings, qualifier, term, opts \\ []) do
    order = get_arg!(opts, :order, :asc, @order_types)
    index_name = Keyword.get(opts, :index_name, nil)
    pre_filter = get_arg!(opts, :pre_filter, false, @true_false)
    score_key = Keyword.get(opts, :score_key, :none)
    score_threshold = Keyword.get(opts, :score_threshold, nil)

    raise_if(
      score_key != :none and not is_atom(score_key),
      "The `score_key` option must be an atom or :none."
    )

    raise_if(
      score_threshold != nil and index_name == nil,
      "The `index_name` option is required when using `score_threshold`."
    )

    {bm25query_fragment, bm25query_params} = query_parts(term, index_name)

    # Score fragment for ordering and selection
    score_fragment_string = "? <@> #{bm25query_fragment}"

    # Build score fragment AST
    score_fragment =
      quote do
        fragment(
          unquote(score_fragment_string),
          unquote(qualifier),
          unquote_splicing(
            Enum.map(bm25query_params, fn param ->
              quote do: ^unquote(param)
            end)
          )
        )
      end

    # Build order fragment if needed
    order_fragment =
      if order != :none do
        asc_desc = if order == :desc, do: :desc, else: :asc

        quote do
          [{unquote(asc_desc), unquote(score_fragment)}]
        end
      end

    # BM25 scores are negative (lower = better), so "better than threshold" means score < threshold
    # (e.g., -5.0 is better than -2.0, so threshold -3.0 keeps scores < -3.0 like -4.0, -5.0)
    threshold_fragment_string = "? <@> #{bm25query_fragment} < ?"

    # Pre-filtering by match (excludes non-matches)
    # Non-matches have score = 0, matches have score < 0
    pre_filter_fragment_string = "? <@> #{bm25query_fragment} < 0"

    # Build the query
    quote do
      unquote(query)
      |> apply_if(unquote(pre_filter), fn q ->
        where(
          q,
          [unquote_splicing(bindings)],
          fragment(
            unquote(pre_filter_fragment_string),
            unquote(qualifier),
            unquote_splicing(
              Enum.map(bm25query_params, fn param ->
                quote do: ^unquote(param)
              end)
            )
          )
        )
      end)
      |> apply_if(unquote(score_threshold) != nil, fn q ->
        where(
          q,
          [unquote_splicing(bindings)],
          fragment(
            unquote(threshold_fragment_string),
            unquote(qualifier),
            unquote_splicing(
              Enum.map(bm25query_params, fn param ->
                quote do: ^unquote(param)
              end)
            ),
            ^unquote(score_threshold)
          )
        )
      end)
      |> apply_if(unquote(order) != :none, fn q ->
        order_by(q, [unquote_splicing(bindings)], unquote(order_fragment))
      end)
      |> apply_if(unquote(score_key) != :none, fn q ->
        select_merge(
          q,
          [unquote_splicing(bindings)],
          %{unquote(score_key) => unquote(score_fragment)}
        )
      end)
    end
  end

  def branch(bindings, qualifier, term, opts) do
    index_name = Keyword.get(opts, :index_name, nil)
    pre_filter = get_arg!(opts, :pre_filter, false, @true_false)
    score_threshold = Keyword.get(opts, :score_threshold, nil)

    raise_if(
      score_threshold != nil and index_name == nil,
      "The `index_name` option is required when using `score_threshold`."
    )

    {bm25query_fragment, bm25query_params} = query_parts(term, index_name)
    params_asts = Enum.map(bm25query_params, fn param -> quote do: ^unquote(param) end)

    rank =
      quote do
        fragment(
          unquote("? <@> #{bm25query_fragment}"),
          unquote(qualifier),
          unquote_splicing(params_asts)
        )
      end

    pre_filter_filters =
      if pre_filter do
        [
          quote do
            dynamic(
              [unquote_splicing(bindings)],
              fragment(
                unquote("? <@> #{bm25query_fragment} < 0"),
                unquote(qualifier),
                unquote_splicing(params_asts)
              )
            )
          end
        ]
      else
        []
      end

    threshold_filters =
      if score_threshold != nil do
        [
          quote do
            dynamic(
              [unquote_splicing(bindings)],
              fragment(
                unquote("? <@> #{bm25query_fragment} < ?"),
                unquote(qualifier),
                unquote_splicing(params_asts),
                ^unquote(score_threshold)
              )
            )
          end
        ]
      else
        []
      end

    {pre_filter_filters ++ threshold_filters, :asc, rank, []}
  end

  # When index_name is provided, use to_bm25query(?, ?) for explicit index specification
  # Otherwise use bare string literal (?) to let PostgreSQL auto-detect the index
  defp query_parts(term, index_name) do
    if index_name do
      {"to_bm25query(?, ?)", [term, index_name]}
    else
      {"?", [term]}
    end
  end
end
