defmodule Torus.Semantic.Embeddings.OpenAI do
  @moduledoc false
  use Torus.Case, async: true

  test "generate/2" do
    Req.Test.stub(:req_plug, fn conn ->
      Req.Test.json(conn, %{
        "data" => [
          %{
            "embedding" => [
              -0.005540426,
              0.0047363234,
              -0.015009919
            ],
            "index" => 0,
            "object" => "embedding"
          },
          %{
            "embedding" => [
              0.005848083,
              -0.008844261,
              -0.025311498
            ],
            "index" => 1,
            "object" => "embedding"
          }
        ],
        "model" => "text-embedding-ada-002-v2",
        "object" => "list",
        "usage" => %{"prompt_tokens" => 6, "total_tokens" => 6}
      })
    end)

    Application.put_env(:torus, Torus.Embeddings.OpenAI, token: "token")
    terms = ["Hello world", "Elixir is great"]

    # This cryptic binary data corresponds to vectorized embeddings
    assert [
             %Pgvector{data: "\0\x03\0\0\xBB\xB5\x8Cv;\x9B3)\xBCu\xEC*"},
             %Pgvector{data: "\0\x03\0\0;\xBF\xA1G\xBC\x10煼\xCFZ\x0F"}
           ] = Torus.Embeddings.OpenAI.generate(terms)
  end
end
