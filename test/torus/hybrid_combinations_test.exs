defmodule Torus.HybridCombinationsTest do
  @moduledoc false
  use Torus.Case, async: true

  import Ecto.Query

  defp rrf(rank, k \\ 60, weight \\ 1.0), do: weight * (1.0 / (k + rank))

  # Per-branch expected ranks with this data and these terms:
  #   full_text "wand"      -> only "hogwarts wand" matches (rank 1)
  #   similarity "hogwarts" -> hogwarts wand (1), hogwart (2), owl post (3)
  #   semantic [1, 0, 0]    -> hogwarts wand (1), hogwart (2), owl post (3)
  setup do
    insert_post!(title: "hogwarts wand", body: "A wand chooses the wizard.")
    insert_post!(title: "hogwart", body: "Almost the school.")
    insert_post!(title: "owl post", body: "Mail delivery by owls.")

    Repo.update_all(where(Post, title: "hogwarts wand"),
      set: [embedding: Pgvector.new([1.0, 0.0, 0.0])]
    )

    Repo.update_all(where(Post, title: "hogwart"),
      set: [embedding: Pgvector.new([0.9, 0.1, 0.0])]
    )

    Repo.update_all(where(Post, title: "owl post"),
      set: [embedding: Pgvector.new([0.0, 0.0, 1.0])]
    )

    %{search_vector: Pgvector.new([1.0, 0.0, 0.0])}
  end

  defp titles_and_scores(query) do
    query
    |> select([p, torus_hybrid: fused], {p.title, fused.score})
    |> Repo.all()
  end

  describe "executed combinations (no bm25)" do
    test "full_text alone" do
      results =
        Post
        |> Torus.hybrid([p], full_text: {[p.title, p.body], "wand"})
        |> titles_and_scores()

      assert [{"hogwarts wand", score}] = results
      assert_in_delta score, rrf(1), 1.0e-12
    end

    test "similarity alone" do
      results =
        Post
        |> Torus.hybrid([p], similarity: {[p.title], "hogwarts"})
        |> titles_and_scores()

      assert [{"hogwarts wand", first}, {"hogwart", second}, {"owl post", third}] = results
      assert_in_delta first, rrf(1), 1.0e-12
      assert_in_delta second, rrf(2), 1.0e-12
      assert_in_delta third, rrf(3), 1.0e-12
    end

    test "semantic alone", %{search_vector: search_vector} do
      results =
        Post
        |> Torus.hybrid([p], semantic: {p.embedding, search_vector, distance: :cosine_distance})
        |> titles_and_scores()

      assert [{"hogwarts wand", first}, {"hogwart", second}, {"owl post", third}] = results
      assert_in_delta first, rrf(1), 1.0e-12
      assert_in_delta second, rrf(2), 1.0e-12
      assert_in_delta third, rrf(3), 1.0e-12
    end

    test "full_text + similarity" do
      results =
        Post
        |> Torus.hybrid([p],
          full_text: {[p.title, p.body], "wand"},
          similarity: {[p.title], "hogwarts"}
        )
        |> titles_and_scores()

      assert [{"hogwarts wand", first}, {"hogwart", second}, {"owl post", third}] = results
      assert_in_delta first, rrf(1) + rrf(1), 1.0e-12
      assert_in_delta second, rrf(2), 1.0e-12
      assert_in_delta third, rrf(3), 1.0e-12
    end

    test "full_text + semantic", %{search_vector: search_vector} do
      results =
        Post
        |> Torus.hybrid([p],
          full_text: {[p.title, p.body], "wand"},
          semantic: {p.embedding, search_vector, distance: :cosine_distance}
        )
        |> titles_and_scores()

      assert [{"hogwarts wand", first}, {"hogwart", second}, {"owl post", third}] = results
      assert_in_delta first, rrf(1) + rrf(1), 1.0e-12
      assert_in_delta second, rrf(2), 1.0e-12
      assert_in_delta third, rrf(3), 1.0e-12
    end

    test "similarity + semantic", %{search_vector: search_vector} do
      results =
        Post
        |> Torus.hybrid([p],
          similarity: {[p.title], "hogwarts"},
          semantic: {p.embedding, search_vector, distance: :cosine_distance}
        )
        |> titles_and_scores()

      assert [{"hogwarts wand", first}, {"hogwart", second}, {"owl post", third}] = results
      assert_in_delta first, rrf(1) + rrf(1), 1.0e-12
      assert_in_delta second, rrf(2) + rrf(2), 1.0e-12
      assert_in_delta third, rrf(3) + rrf(3), 1.0e-12
    end

    test "full_text + similarity + semantic", %{search_vector: search_vector} do
      results =
        Post
        |> Torus.hybrid([p],
          full_text: {[p.title, p.body], "wand"},
          similarity: {[p.title], "hogwarts"},
          semantic: {p.embedding, search_vector, distance: :cosine_distance}
        )
        |> titles_and_scores()

      assert [{"hogwarts wand", first}, {"hogwart", second}, {"owl post", third}] = results
      assert_in_delta first, rrf(1) + rrf(1) + rrf(1), 1.0e-12
      assert_in_delta second, rrf(2) + rrf(2), 1.0e-12
      assert_in_delta third, rrf(3) + rrf(3), 1.0e-12
    end
  end

  # pg_textsearch (the `<@>` bm25 operator) isn't installed in the local test
  # database, so bm25-involving combinations are verified at the generated-SQL
  # level - the same approach the main hybrid suite uses for its bm25 branch.
  describe "bm25 combinations (generated SQL)" do
    defp raw_sql(query) do
      {sql, _params} = Ecto.Adapters.SQL.to_sql(:all, Repo, query)
      sql
    end

    defp assert_branch_markers(sql, markers) do
      assert sql =~ "row_number()"
      assert sql =~ "UNION ALL"

      for marker <- markers do
        assert sql =~ marker
      end
    end

    test "bm25 alone" do
      sql =
        Post
        |> Torus.hybrid([p], bm25: {p.body, "search"})
        |> QueryInspector.substituted_sql()

      assert sql =~ "row_number()"
      assert sql =~ "<@> 'search'"
      # An empty term must contribute no rows to the fusion
      assert sql =~ "trim('search') <> ''"
    end

    test "bm25 + full_text" do
      sql =
        Post
        |> Torus.hybrid([p],
          bm25: {p.body, "search"},
          full_text: {[p.title, p.body], "wand"}
        )
        |> raw_sql()

      assert_branch_markers(sql, ["<@>", "websearch_to_tsquery"])
    end

    test "bm25 + similarity" do
      sql =
        Post
        |> Torus.hybrid([p],
          bm25: {p.body, "search"},
          similarity: {[p.title], "hogwarts"}
        )
        |> raw_sql()

      assert_branch_markers(sql, ["<@>", "word_similarity"])
    end

    test "bm25 + semantic", %{search_vector: search_vector} do
      sql =
        Post
        |> Torus.hybrid([p],
          bm25: {p.body, "search"},
          semantic: {p.embedding, search_vector, distance: :cosine_distance}
        )
        |> raw_sql()

      assert_branch_markers(sql, ["<@>", "<=>"])
    end

    test "bm25 + full_text + similarity" do
      sql =
        Post
        |> Torus.hybrid([p],
          bm25: {p.body, "search"},
          full_text: {[p.title, p.body], "wand"},
          similarity: {[p.title], "hogwarts"}
        )
        |> raw_sql()

      assert_branch_markers(sql, ["<@>", "websearch_to_tsquery", "word_similarity"])
    end

    test "bm25 + full_text + semantic", %{search_vector: search_vector} do
      sql =
        Post
        |> Torus.hybrid([p],
          bm25: {p.body, "search"},
          full_text: {[p.title, p.body], "wand"},
          semantic: {p.embedding, search_vector, distance: :cosine_distance}
        )
        |> raw_sql()

      assert_branch_markers(sql, ["<@>", "websearch_to_tsquery", "<=>"])
    end

    test "bm25 + similarity + semantic", %{search_vector: search_vector} do
      sql =
        Post
        |> Torus.hybrid([p],
          bm25: {p.body, "search"},
          similarity: {[p.title], "hogwarts"},
          semantic: {p.embedding, search_vector, distance: :cosine_distance}
        )
        |> raw_sql()

      assert_branch_markers(sql, ["<@>", "word_similarity", "<=>"])
    end

    test "all four branch types", %{search_vector: search_vector} do
      sql =
        Post
        |> Torus.hybrid([p],
          bm25: {p.body, "search"},
          full_text: {[p.title, p.body], "wand"},
          similarity: {[p.title], "hogwarts"},
          semantic: {p.embedding, search_vector, distance: :cosine_distance}
        )
        |> raw_sql()

      assert_branch_markers(sql, [
        "<@>",
        "websearch_to_tsquery",
        "word_similarity",
        "<=>"
      ])
    end
  end
end
