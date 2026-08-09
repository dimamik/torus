defmodule Torus.HybridTest do
  @moduledoc false
  use Torus.Case, async: true

  import Ecto.Query

  defp rrf(rank, k \\ 60, weight \\ 1.0), do: weight * (1.0 / (k + rank))

  describe "hybrid/4 - fusion" do
    setup do
      insert_post!(title: "hogwarts wand", body: "A wand chooses the wizard.")
      insert_post!(title: "hogwart", body: "Almost the school.")
      insert_post!(title: "owl post", body: "Mail delivery by owls.")

      :ok
    end

    test "fuses ranks with hand-computed RRF scores" do
      results =
        Post
        |> Torus.hybrid([p],
          full_text: {[p.title, p.body], "wand"},
          similarity: {[p.title], "hogwarts"}
        )
        |> select([p, torus_hybrid: fused], {p.title, fused.score})
        |> Repo.all()

      assert [{"hogwarts wand", first}, {"hogwart", second}, {"owl post", third}] = results

      # "hogwarts wand" is rank 1 in both branches, the others match similarity only
      assert_in_delta first, rrf(1) + rrf(1), 1.0e-12
      assert_in_delta second, rrf(2), 1.0e-12
      assert_in_delta third, rrf(3), 1.0e-12
    end

    test "weights scale branch contributions" do
      results =
        Post
        |> Torus.hybrid([p],
          full_text: {[p.title, p.body], "wand", weight: 2.0},
          similarity: {[p.title], "hogwarts", weight: 0.5}
        )
        |> select([p, torus_hybrid: fused], {p.title, fused.score})
        |> Repo.all()

      assert [{"hogwarts wand", first} | _rest] = results
      assert_in_delta first, rrf(1, 60, 2.0) + rrf(1, 60, 0.5), 1.0e-12
    end

    test "the same branch type can appear more than once" do
      results =
        Post
        |> Torus.hybrid([p],
          similarity: {[p.title], "hogwarts", weight: 2.0},
          similarity: {[p.body], "wand", weight: 0.5}
        )
        |> select([p, torus_hybrid: fused], {p.title, fused.score})
        |> Repo.all()

      assert [{"hogwarts wand", first}, _second, _third] = results
      assert_in_delta first, rrf(1, 60, 2.0) + rrf(1, 60, 0.5), 1.0e-12
    end

    test "an empty full_text term contributes no rows to the fusion" do
      results =
        Post
        |> Torus.hybrid([p],
          full_text: {[p.title, p.body], ""},
          similarity: {[p.title], "hogwarts"}
        )
        |> select([p, torus_hybrid: fused], {p.title, fused.score})
        |> Repo.all()

      # Only the similarity branch contributes - full_text adds nothing for an empty term
      assert [{"hogwarts wand", first}, {"hogwart", second}, {"owl post", third}] = results
      assert_in_delta first, rrf(1), 1.0e-12
      assert_in_delta second, rrf(2), 1.0e-12
      assert_in_delta third, rrf(3), 1.0e-12
    end

    test "full_text branch supports filter_type: :concat" do
      results =
        Post
        |> Torus.hybrid([p], full_text: {[p.title, p.body], "wand", filter_type: :concat})
        |> select([p], p.title)
        |> Repo.all()

      assert ["hogwarts wand"] = results
    end

    test "bm25 branch generates a ranked <@> subquery" do
      sql =
        Post
        |> Torus.hybrid([p], bm25: {p.body, "search"})
        |> QueryInspector.substituted_sql()

      assert sql =~ "row_number()"
      assert sql =~ ~s|<@> 'search'|
    end

    test "semantic branch pre_filter excludes distant rows" do
      Repo.update_all(where(Post, title: "hogwarts wand"),
        set: [embedding: Pgvector.new([1.0, 0.0, 0.0])]
      )

      Repo.update_all(where(Post, title: "hogwart"),
        set: [embedding: Pgvector.new([0.9, 0.1, 0.0])]
      )

      Repo.update_all(where(Post, title: "owl post"),
        set: [embedding: Pgvector.new([0.0, 0.0, 1.0])]
      )

      search_vector = Pgvector.new([1.0, 0.0, 0.0])

      results =
        Post
        |> Torus.hybrid([p],
          semantic: {p.embedding, search_vector, distance: :cosine_distance, pre_filter: 0.5}
        )
        |> select([p], p.title)
        |> Repo.all()

      assert ["hogwarts wand", "hogwart"] = results
    end

    test ":primary_key fuses schemaless queries" do
      results =
        from(p in "posts")
        |> Torus.hybrid([p], [similarity: {[p.title], "hogwarts"}], primary_key: :id)
        |> select([p], p.title)
        |> Repo.all()

      assert ["hogwarts wand", "hogwart", "owl post"] = results
    end

    test "custom k changes the smoothing" do
      results =
        Post
        |> Torus.hybrid([p], [similarity: {[p.title], "hogwarts"}], k: 1)
        |> select([p, torus_hybrid: fused], {p.title, fused.score})
        |> Repo.all()

      assert [{"hogwarts wand", first} | _rest] = results
      assert_in_delta first, rrf(1, 1), 1.0e-12
    end

    test "semantic branch fuses with keyword branches" do
      Repo.update_all(where(Post, title: "hogwarts wand"),
        set: [embedding: Pgvector.new([1.0, 0.0, 0.0])]
      )

      Repo.update_all(where(Post, title: "hogwart"),
        set: [embedding: Pgvector.new([0.9, 0.1, 0.0])]
      )

      Repo.update_all(where(Post, title: "owl post"),
        set: [embedding: Pgvector.new([0.0, 0.0, 1.0])]
      )

      search_vector = Pgvector.new([1.0, 0.0, 0.0])

      results =
        Post
        |> Torus.hybrid([p],
          full_text: {[p.title, p.body], "wand"},
          similarity: {[p.title], "hogwarts"},
          semantic: {p.embedding, search_vector, distance: :cosine_distance}
        )
        |> select([p], p.title)
        |> Repo.all()

      assert ["hogwarts wand", "hogwart", "owl post"] = results
    end

    test "discards order_by piped in before the fusion" do
      results =
        Post
        |> order_by([p], desc: p.title)
        |> Torus.hybrid([p], similarity: {[p.title], "hogwarts"})
        |> select([p], p.title)
        |> Repo.all()

      assert ["hogwarts wand", "hogwart", "owl post"] = results
    end

    test "preload piped in before the fusion applies to the result" do
      author = insert_author!(name: "Rita Skeeter")
      Repo.update_all(Post, set: [author_id: author.id])

      results =
        Post
        |> preload(:author)
        |> Torus.hybrid([p], similarity: {[p.title], "hogwarts"})
        |> Repo.all()

      assert [%Post{title: "hogwarts wand", author: %Author{name: "Rita Skeeter"}} | _rest] =
               results
    end

    test "offset piped in before the fusion skips fused rows, not branch rows" do
      results =
        Post
        |> offset(1)
        |> Torus.hybrid([p], similarity: {[p.title], "hogwarts"})
        |> select([p], p.title)
        |> Repo.all()

      assert ["hogwart", "owl post"] = results
    end

    test "base query filters apply to every branch" do
      results =
        Post
        |> where([p], p.title != "hogwarts wand")
        |> Torus.hybrid([p], similarity: {[p.title], "hogwarts"})
        |> select([p], p.title)
        |> Repo.all()

      assert ["hogwart", "owl post"] = results
    end

    test "score_key merges the fused score into a map select" do
      results =
        Post
        |> select([p], %{title: p.title})
        |> Torus.hybrid([p], [similarity: {[p.title], "hogwarts"}], score_key: :score)
        |> Repo.all()

      assert [%{title: "hogwarts wand", score: score} | _rest] = results
      assert_in_delta score, rrf(1), 1.0e-12
    end

    test "stays composable after fusion" do
      author = insert_author!(name: "Rita Skeeter")
      Repo.update_all(Post, set: [author_id: author.id])

      results =
        Post
        |> Torus.hybrid([p], [similarity: {[p.title], "hogwarts"}], limit: 2)
        |> where([p], p.title != "hogwart")
        |> preload(:author)
        |> Repo.all()

      assert [
               %Post{title: "hogwarts wand", author: %Author{name: "Rita Skeeter"}},
               %Post{title: "owl post"}
             ] = results
    end
  end

  describe "hybrid/4 - branch limits and determinism" do
    test "branch limit caps how many rows a branch contributes" do
      for index <- 1..30, do: insert_post!(title: "filler #{index} zzz")
      insert_post!(title: "hogwarts")

      results =
        Post
        |> Torus.hybrid([p], similarity: {[p.title], "hogwarts", limit: 5})
        |> select([p], p.title)
        |> Repo.all()

      assert length(results) == 5
      assert ["hogwarts" | _rest] = results
    end

    test "ties within a branch rank deterministically by primary key" do
      posts = for _index <- 1..3, do: insert_post!(title: "same title")

      results =
        Post
        |> Torus.hybrid([p], similarity: {[p.title], "same title"})
        |> select([p, torus_hybrid: fused], {p.id, fused.score})
        |> Repo.all()

      assert Enum.map(results, &elem(&1, 0)) == Enum.map(posts, & &1.id)

      for {{_id, score}, rank} <- Enum.with_index(results, 1) do
        assert_in_delta score, rrf(rank), 1.0e-12
      end
    end

    test "returns the same order across runs" do
      for index <- 1..30, do: insert_post!(title: "filler #{index} zzz")
      insert_post!(title: "hogwarts")
      insert_post!(title: "hogwart")

      query =
        Post
        |> Torus.hybrid([p],
          full_text: {[p.title, p.body], "hogwarts"},
          similarity: {[p.title], "hogwarts"}
        )
        |> select([p], p.id)

      first_run = Repo.all(query)
      second_run = Repo.all(query)

      assert first_run == second_run
    end
  end

  describe "hybrid/4 - errors" do
    test "raises on a runtime (non-literal) branch list" do
      code = """
      import Ecto.Query
      import Torus
      alias TorusTest.Post

      searches = []
      Post |> Torus.hybrid([p], searches)
      """

      assert_raise RuntimeError, ~r/compile-time keyword list of search branches/, fn ->
        Code.eval_string(code, [], __ENV__)
      end
    end

    test "raises on an unsupported branch type" do
      code = """
      import Ecto.Query
      import Torus
      alias TorusTest.Post

      Post |> Torus.hybrid([p], ilike: {[p.title], "hog%"})
      """

      assert_raise RuntimeError, ~r/compile-time keyword list of search branches/, fn ->
        Code.eval_string(code, [], __ENV__)
      end
    end

    test "raises on the `order` branch option" do
      code = """
      import Ecto.Query
      import Torus
      alias TorusTest.Post

      Post |> Torus.hybrid([p], similarity: {[p.title], "hog", order: :asc})
      """

      assert_raise RuntimeError, ~r/`order` option is not supported/, fn ->
        Code.eval_string(code, [], __ENV__)
      end
    end

    test "raises on the `score_key` and `distance_key` branch options" do
      for branch <- [
            ~s|bm25: {p.title, "hog", score_key: :score}|,
            ~s|semantic: {p.embedding, "vector", distance_key: :distance}|
          ] do
        code = """
        import Ecto.Query
        import Torus
        alias TorusTest.Post

        Post |> Torus.hybrid([p], #{branch})
        """

        assert_raise RuntimeError, ~r/option is not supported in hybrid branches/, fn ->
          Code.eval_string(code, [], __ENV__)
        end
      end
    end

    test "raises on a malformed branch spec" do
      code = """
      import Ecto.Query
      import Torus
      alias TorusTest.Post

      Post |> Torus.hybrid([p], similarity: [p.title])
      """

      assert_raise RuntimeError, ~r/must be a `{qualifiers, term}`/, fn ->
        Code.eval_string(code, [], __ENV__)
      end
    end

    test "raises on invalid literal options" do
      for {options, message} <- [
            {~s|[k: "sixty"]|, ~r/`k` option must be a positive number/},
            {"[k: 0]", ~r/`k` option must be a positive number/},
            {"[score_key: nil]", ~r/`score_key` option must be a non-nil atom/}
          ] do
        code = """
        import Ecto.Query
        import Torus
        alias TorusTest.Post

        Post |> Torus.hybrid([p], [similarity: {[p.title], "hog"}], #{options})
        """

        assert_raise RuntimeError, message, fn ->
          Code.eval_string(code, [], __ENV__)
        end
      end
    end

    test "raises on invalid literal branch options" do
      for {branch_options, message} <- [
            {~s|weight: "2.0"|, ~r/`weight` of a hybrid branch must be a non-negative number/},
            {"weight: -1.0", ~r/`weight` of a hybrid branch must be a non-negative number/},
            {"limit: 0", ~r/`limit` of a hybrid branch must be a positive integer/},
            {"limit: 2.5", ~r/`limit` of a hybrid branch must be a positive integer/}
          ] do
        code = """
        import Ecto.Query
        import Torus
        alias TorusTest.Post

        Post |> Torus.hybrid([p], similarity: {[p.title], "hog", #{branch_options}})
        """

        assert_raise RuntimeError, message, fn ->
          Code.eval_string(code, [], __ENV__)
        end
      end
    end

    test "raises on a schemaless query without :primary_key" do
      assert_raise ArgumentError, ~r/schemaless query/, fn ->
        from(p in "posts")
        |> Torus.hybrid([p], similarity: {[p.title], "hogwarts"})
      end
    end

    test "raises on a non-float semantic pre_filter" do
      code = """
      import Ecto.Query
      import Torus
      alias TorusTest.Post

      Post |> Torus.hybrid([p], semantic: {p.embedding, "vector", pre_filter: 1})
      """

      assert_raise RuntimeError, ~r/must be a literal float/, fn ->
        Code.eval_string(code, [], __ENV__)
      end
    end

    test "semantic branch raises on a non-Pgvector term" do
      assert_raise RuntimeError, ~r/should be a Pgvector struct/, fn ->
        Post |> Torus.hybrid([p], semantic: {p.embedding, "not a vector"})
      end
    end
  end
end
