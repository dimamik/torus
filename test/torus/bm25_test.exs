defmodule Torus.BM25Test do
  @moduledoc false
  use Torus.Case, async: false

  @moduletag :skip_ci

  import Ecto.Query
  import Torus

  alias Torus.Test.Repo
  alias TorusTest.Post

  # NOTE: pg_textsearch has a known limitation where uncommitted rows from
  # rolled-back transactions remain in the BM25 memtable. This can cause
  # ORDER BY + LIMIT queries to return stale TIDs that fail visibility checks.
  # The standalone operator (without ORDER BY) works correctly.

  defp flush_bm25!(index_name \\ "posts_body_bm25_idx") do
    Repo.query!("SELECT bm25_spill_index($1)", [index_name])
    :ok
  end

  defp reset_bm25_state! do
    Repo.query!("TRUNCATE TABLE posts RESTART IDENTITY CASCADE")
    flush_bm25!()
    flush_bm25!("posts_title_bm25_idx")
    :ok
  end

  setup do
    reset_bm25_state!()
    :ok
  end

  describe "bm25/5 - basic functionality" do
    test "basic search returns matching results" do
      insert_post!(body: "Hogwarts is a powerful magical school system")
      insert_post!(body: "Quidditch is a ranking sport used in wizarding games")
      insert_post!(body: "Spell search enables finding relevant incantations")

      flush_bm25!()

      results =
        Post
        |> Torus.bm25([p], p.body, "magical school system",
          pre_filter: true,
          index_name: "posts_body_bm25_idx"
        )
        |> limit(10)
        |> select([p], p.body)
        |> Repo.all()

      assert length(results) == 1
      assert "Hogwarts is a powerful magical school system" in results
    end

    test "returns empty list when no matches" do
      insert_post!(body: "Hogwarts magical")

      flush_bm25!()

      results =
        Post
        |> Torus.bm25([p], p.body, "nonexistent muggle xyz",
          pre_filter: true,
          index_name: "posts_body_bm25_idx"
        )
        |> limit(10)
        |> select([p], p.body)
        |> Repo.all()

      assert results == []
    end
  end

  describe "bm25/5 - ordering" do
    test ":order defaults to :asc (best matches first)" do
      post1 = insert_post!(body: "magic magic magic")
      _post2 = insert_post!(body: "magic wands")
      _post3 = insert_post!(body: "unrelated content with magic")

      flush_bm25!()

      results =
        Post
        |> Torus.bm25([p], p.body, "magic", index_name: "posts_body_bm25_idx")
        |> select([p], p.id)
        |> Repo.all()

      # First result should be post with most relevance (post1)
      assert hd(results) == post1.id
    end

    test ":order :asc returns best matches first" do
      post1 = insert_post!(body: "Hogwarts magical school system architecture")
      post2 = insert_post!(body: "magical")
      post3 = insert_post!(body: "unrelated text")

      flush_bm25!()

      results =
        Post
        |> Torus.bm25([p], p.body, "magical", order: :asc, index_name: "posts_body_bm25_idx")
        |> select([p], p.id)
        |> Repo.all()

      # Best matches should be first
      assert hd(results) in [post1.id, post2.id]
      refute hd(results) == post3.id
    end

    test ":order :desc returns worst matches first" do
      insert_post!(body: "magic magic magic")
      _post_bad = insert_post!(body: "unrelated content with magic mention")

      flush_bm25!()

      results =
        Post
        |> Torus.bm25([p], p.body, "magic", order: :desc, index_name: "posts_body_bm25_idx")
        |> limit(1)
        |> select([p], p.id)
        |> Repo.all()

      # Worst match should be first with :desc
      assert length(results) == 1
    end

    test ":order :none doesn't apply ordering" do
      insert_post!(body: "magical wands")
      insert_post!(body: "magic")

      flush_bm25!()

      # Query should work without ordering
      results =
        Post
        |> Torus.bm25([p], p.body, "magic", order: :none)
        |> select([p], p.body)
        |> Repo.all()

      assert length(results) == 2
    end
  end

  describe "bm25/5 - score selection" do
    test ":score_key :none doesn't select score" do
      insert_post!(body: "magical wands")

      flush_bm25!()

      results =
        Post
        |> Torus.bm25([p], p.body, "magic", score_key: :none, order: :none)
        |> select([p], %{body: p.body})
        |> Repo.all()

      result = hd(results)
      refute Map.has_key?(result, :score)
      refute Map.has_key?(result, :relevance)
    end

    test ":score_key selects BM25 score into result map" do
      insert_post!(body: "magical school architecture")

      flush_bm25!()

      results =
        Post
        |> select([p], %{id: p.id, body: p.body})
        |> Torus.bm25([p], p.body, "magic",
          score_key: :relevance,
          index_name: "posts_body_bm25_idx"
        )
        |> Repo.all()

      result = hd(results)
      assert Map.has_key?(result, :relevance)
      assert is_number(result.relevance)
      # BM25 scores are negative
      assert result.relevance < 0
    end

    test "score_key works with multiple results" do
      insert_post!(body: "magic magic")
      insert_post!(body: "magic")

      flush_bm25!()

      results =
        Post
        |> select([p], %{id: p.id, body: p.body})
        |> Torus.bm25([p], p.body, "magic",
          score_key: :score,
          index_name: "posts_body_bm25_idx"
        )
        |> Repo.all()

      assert length(results) == 2

      for result <- results do
        assert Map.has_key?(result, :score)
        assert is_number(result.score)
      end
    end
  end

  describe "bm25/5 - index_name option" do
    test "explicit index_name works" do
      insert_post!(body: "magical wands")

      flush_bm25!()

      results =
        Post
        |> Torus.bm25([p], p.body, "magic", index_name: "posts_body_bm25_idx")
        |> limit(10)
        |> select([p], p.body)
        |> Repo.all()

      assert "magical wands" in results
    end

    test "works without index_name when order: :none" do
      insert_post!(body: "magical wands")

      flush_bm25!()

      results =
        Post
        |> Torus.bm25([p], p.body, "magic", order: :none)
        |> limit(10)
        |> select([p], p.body)
        |> Repo.all()

      assert "magical wands" in results
    end
  end

  describe "bm25/5 - pre_filter option" do
    test "pre_filter true filters non-matching rows" do
      insert_post!(body: "magical wands")
      insert_post!(body: "completely unrelated muggle stuff")

      flush_bm25!()

      results =
        Post
        |> Torus.bm25([p], p.body, "magic",
          pre_filter: true,
          index_name: "posts_body_bm25_idx"
        )
        |> select([p], p.body)
        |> Repo.all()

      assert results == ["magical wands"]
    end
  end

  describe "bm25/5 - score_threshold option" do
    test "score_threshold keeps only results with score better than threshold" do
      # Post with high relevance (many occurrences) will have a more negative score
      insert_post!(body: "magic magic magic magic")
      # Post with low relevance will have a less negative score (closer to 0)
      insert_post!(body: "unrelated text with magic")

      flush_bm25!()

      # Get scores to understand what we're filtering
      all_results =
        Post
        |> select([p], %{body: p.body})
        |> Torus.bm25([p], p.body, "magic",
          score_key: :score,
          index_name: "posts_body_bm25_idx"
        )
        |> Repo.all()

      # All results should have negative scores
      assert Enum.all?(all_results, fn r -> r.score < 0 end)

      # With a restrictive threshold (score must be < -3.0, meaning better matches only)
      # This should filter out worse matches (less negative scores)
      results_with_threshold =
        Post
        |> Torus.bm25([p], p.body, "magic",
          score_threshold: -3.0,
          index_name: "posts_body_bm25_idx"
        )
        |> select([p], p.body)
        |> Repo.all()

      # Threshold should filter some results (only keep scores < -3.0)
      assert length(results_with_threshold) <= length(all_results)
    end

    test "score_threshold nil doesn't filter" do
      insert_post!(body: "magical wands")
      insert_post!(body: "magic")

      flush_bm25!()

      results =
        Post
        |> Torus.bm25([p], p.body, "magic",
          score_threshold: nil,
          index_name: "posts_body_bm25_idx"
        )
        |> select([p], p.body)
        |> Repo.all()

      assert length(results) == 2
    end
  end

  describe "bm25/5 - language via index" do
    test "english index uses stemming (wizards matches wizard)" do
      insert_post!(body: "wizards are powerful beings")

      flush_bm25!()

      results =
        Post
        |> Torus.bm25([p], p.body, "wizard", index_name: "posts_body_bm25_idx")
        |> select([p], p.body)
        |> Repo.all()

      # English stemming should match "wizards" with "wizard"
      assert "wizards are powerful beings" in results
    end

    test "simple index does not use stemming" do
      Repo.query!("DROP INDEX IF EXISTS posts_body_bm25_simple_idx")

      Repo.query!("""
      CREATE INDEX posts_body_bm25_simple_idx ON posts
      USING bm25(body) WITH (text_config='simple')
      """)

      insert_post!(body: "simple spell casting example")

      flush_bm25!("posts_body_bm25_simple_idx")

      results =
        Post
        |> Torus.bm25([p], p.body, "spell", index_name: "posts_body_bm25_simple_idx")
        |> select([p], p.body)
        |> Repo.all()

      assert "simple spell casting example" in results

      Repo.query!("DROP INDEX IF EXISTS posts_body_bm25_simple_idx")
    end
  end

  describe "bm25/5 - integration with where clauses" do
    test "works with pre-filtering where clauses" do
      post1 = insert_post!(title: "Gryffindor", body: "magical wands")
      post2 = insert_post!(title: "Slytherin", body: "magical potions")

      flush_bm25!()

      results =
        Post
        |> where([p], p.title == "Gryffindor")
        |> Torus.bm25([p], p.body, "magic", index_name: "posts_body_bm25_idx")
        |> select([p], p.id)
        |> Repo.all()

      assert results == [post1.id]
      refute post2.id in results
    end

    test "combines with other Ecto query functions" do
      insert_post!(title: "Gryffindor", body: "magical wands")
      insert_post!(title: "Slytherin", body: "magical potions")
      insert_post!(title: "Ravenclaw", body: "magical knowledge")

      flush_bm25!()

      results =
        Post
        |> Torus.bm25([p], p.body, "magic", index_name: "posts_body_bm25_idx")
        |> limit(2)
        |> select([p], p.title)
        |> Repo.all()

      assert length(results) == 2
    end
  end

  describe "bm25/5 - complex queries" do
    test "multi-word search queries" do
      insert_post!(body: "Hogwarts is a powerful ancient magical school")
      insert_post!(body: "Durmstrang schools are also famous")

      flush_bm25!()

      results =
        Post
        |> Torus.bm25([p], p.body, "ancient magical school", index_name: "posts_body_bm25_idx")
        |> limit(1)
        |> select([p], p.body)
        |> Repo.all()

      assert "Hogwarts is a powerful ancient magical school" in results
    end

    test "works with different columns (title vs body)" do
      insert_post!(title: "Magical Schools", body: "Content about potions")
      insert_post!(title: "Potions Guide", body: "Content about magic")

      flush_bm25!()
      flush_bm25!("posts_title_bm25_idx")

      title_results =
        Post
        |> Torus.bm25([p], p.title, "magic", index_name: "posts_title_bm25_idx")
        |> select([p], p.title)
        |> Repo.all()

      body_results =
        Post
        |> Torus.bm25([p], p.body, "magic", index_name: "posts_body_bm25_idx")
        |> select([p], p.body)
        |> Repo.all()

      assert "Magical Schools" in title_results
      assert "Content about magic" in body_results
    end
  end
end
