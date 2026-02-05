defmodule Torus.BM25CompileTest do
  @moduledoc false
  use ExUnit.Case, async: true

  describe "bm25/5 - compile-time validations" do
    test "score_threshold without index_name raises at compile time" do
      # This test verifies that using score_threshold without index_name
      # results in a compile-time error by attempting to compile code that does so

      code = """
      import Ecto.Query
      import Torus
      alias TorusTest.Post

      Post
      |> Torus.bm25([p], p.body, "search", score_threshold: -5.0)
      |> limit(10)
      """

      assert_raise RuntimeError, ~r/index_name.*required.*score_threshold/i, fn ->
        Code.eval_string(code, [], __ENV__)
      end
    end

    test "score_threshold with index_name compiles successfully" do
      # This should compile without errors
      code = """
      import Ecto.Query
      import Torus
      alias TorusTest.Post

      Post
      |> Torus.bm25([p], p.body, "search", score_threshold: -5.0, index_name: "posts_body_idx")
      |> limit(10)
      """

      assert {_query, _bindings} = Code.eval_string(code, [], __ENV__)
    end
  end
end
