defmodule Torus.Search.Hybrid do
  @moduledoc false
  import Torus.Search.Common
  import Ecto.Query, warn: false

  alias Torus.Search.Hybrid

  @search_modules %{
    full_text: Torus.Search.FullText,
    similarity: Torus.Search.Similarity,
    semantic: Torus.Search.Semantic,
    bm25: Torus.Search.BM25
  }

  @branch_types Map.keys(@search_modules)

  def hybrid(query, bindings, searches, opts) do
    k = Keyword.get(opts, :k, 60)
    final_limit = Keyword.get(opts, :limit, :none)
    score_key = Keyword.get(opts, :score_key, :none)
    primary_key = Keyword.get(opts, :primary_key, nil)
    source = List.first(bindings)

    validate_score_key!(score_key)
    validate_k!(k)

    raise_if(
      not (is_list(searches) and searches != [] and
             Enum.all?(searches, &match?({type, _spec} when type in @branch_types, &1))),
      """
      Torus.hybrid/4 expects a compile-time keyword list of search branches, \
      with keys among: #{inspect(@branch_types)}. For example:

          Torus.hybrid(query, [p], [
            full_text: {[p.title, p.body], term},
            semantic: {p.embedding, vector}
          ])
      """
    )

    branches =
      for {type, spec} <- searches do
        module = Map.fetch!(@search_modules, type)
        {qualifiers, term, branch_opts} = parse_spec(type, spec)
        {weight, branch_opts} = Keyword.pop(branch_opts, :weight, 1.0)
        {branch_limit, branch_opts} = Keyword.pop(branch_opts, :limit, 20)

        raise_if(
          Keyword.has_key?(branch_opts, :order),
          "The `order` option is not supported in hybrid branches - " <>
            "branches are always ranked best-first."
        )

        validate_weight!(weight)
        validate_branch_limit!(branch_limit)

        {filters, direction, rank, preludes} =
          module.branch(bindings, qualifiers, term, branch_opts)

        %{
          filters: filters,
          direction: direction,
          rank: rank,
          preludes: preludes,
          weight: weight,
          limit: branch_limit
        }
      end

    preludes = Enum.flat_map(branches, & &1.preludes)

    wrapped_branches =
      for branch <- branches do
        branch_query = branch_ast(branch, bindings, source)

        quote do
          from(s in subquery(unquote(branch_query)),
            select: %{id: s.id, rank: s.rank, weight: type(^unquote(branch.weight), :float)}
          )
        end
      end

    unioned =
      Enum.reduce(tl(wrapped_branches), hd(wrapped_branches), fn wrapped, acc ->
        quote do
          union_all(unquote(acc), ^unquote(wrapped))
        end
      end)

    fused =
      quote do
        from(b in subquery(unquote(unioned)),
          group_by: b.id,
          select: %{
            id: b.id,
            score: sum(fragment("? * (1.0 / (? + ?))", b.weight, ^unquote(k), b.rank))
          }
        )
      end

    final =
      quote do
        unquote_splicing(preludes)

        torus_hybrid_source_query = Ecto.Queryable.to_query(unquote(query))

        torus_hybrid_primary_key =
          Hybrid.primary_key!(torus_hybrid_source_query, unquote(primary_key))

        torus_hybrid_branch_base =
          torus_hybrid_source_query
          |> Ecto.Query.exclude(:select)
          |> Ecto.Query.exclude(:order_by)

        torus_hybrid_source_query
        |> join(:inner, [unquote_splicing(bindings)], f in subquery(unquote(fused)),
          on: field(unquote(source), ^torus_hybrid_primary_key) == f.id,
          as: :torus_hybrid
        )
        |> order_by([unquote_splicing(bindings), torus_hybrid: f], [
          {:desc, f.score},
          {:asc, field(unquote(source), ^torus_hybrid_primary_key)}
        ])
      end

    final =
      if final_limit == :none do
        final
      else
        quote do
          unquote(final) |> limit(^unquote(final_limit))
        end
      end

    if score_key == :none do
      final
    else
      quote do
        unquote(final)
        |> select_merge([unquote_splicing(bindings), torus_hybrid: f], %{
          unquote(score_key) => f.score
        })
      end
    end
  end

  def primary_key!(_query, primary_key) when is_atom(primary_key) and not is_nil(primary_key) do
    primary_key
  end

  def primary_key!(%Ecto.Query{from: %{source: {_table, schema}}}, nil) when not is_nil(schema) do
    case schema.__schema__(:primary_key) do
      [primary_key] ->
        primary_key

      other ->
        raise ArgumentError, """
        Torus.hybrid/4 requires a single-column primary key, got: #{inspect(other)}.
        Pass the `:primary_key` option to choose the column to fuse on.
        """
    end
  end

  def primary_key!(%Ecto.Query{}, nil) do
    raise ArgumentError, """
    Torus.hybrid/4 can't detect the primary key of a schemaless query.
    Pass the `:primary_key` option to choose the column to fuse on.
    """
  end

  defp branch_ast(branch, bindings, source) do
    filtered =
      Enum.reduce(branch.filters, quote(do: torus_hybrid_branch_base), fn filter, acc ->
        quote do
          where(unquote(acc), ^unquote(filter))
        end
      end)

    quote do
      unquote(filtered)
      |> select([unquote_splicing(bindings)], %{
        id: field(unquote(source), ^torus_hybrid_primary_key),
        rank:
          selected_as(
            over(row_number(),
              order_by: [{unquote(branch.direction), unquote(branch.rank)}]
            ),
            :rank
          )
      })
      |> order_by(selected_as(:rank))
      |> limit(^unquote(branch.limit))
    end
  end

  defp validate_score_key!(score_key) do
    raise_if(
      is_nil(score_key) or not is_atom(score_key),
      "The `score_key` option must be a non-nil atom."
    )
  end

  defp validate_k!(k) do
    k = literal_number(k)

    raise_if(
      is_binary(k) or is_atom(k) or is_list(k) or (is_number(k) and k <= 0),
      "The `k` option must be a positive number."
    )
  end

  defp validate_weight!(weight) do
    weight = literal_number(weight)

    raise_if(
      is_binary(weight) or is_atom(weight) or is_list(weight) or
        (is_number(weight) and weight < 0),
      "The `weight` of a hybrid branch must be a non-negative number."
    )
  end

  defp validate_branch_limit!(branch_limit) do
    branch_limit = literal_number(branch_limit)

    raise_if(
      is_binary(branch_limit) or is_atom(branch_limit) or is_list(branch_limit) or
        is_float(branch_limit) or (is_integer(branch_limit) and branch_limit <= 0),
      "The `limit` of a hybrid branch must be a positive integer."
    )
  end

  # Negative literals appear in the AST as a unary minus, e.g. `-1.0` is
  # `{:-, _meta, [1.0]}` - normalize them so literal validations catch them.
  defp literal_number({:-, _meta, [number]}) when is_number(number), do: -number
  defp literal_number(other), do: other

  defp parse_spec(_type, {qualifiers, term}), do: {qualifiers, term, []}

  defp parse_spec(type, {:{}, _meta, [qualifiers, term, branch_opts]}) do
    raise_if(
      not Keyword.keyword?(branch_opts),
      "The options of the `#{type}` hybrid branch must be a compile-time keyword list."
    )

    {qualifiers, term, branch_opts}
  end

  defp parse_spec(type, _spec) do
    raise "The `#{type}` hybrid branch must be a `{qualifiers, term}` or " <>
            "`{qualifiers, term, opts}` tuple."
  end
end
