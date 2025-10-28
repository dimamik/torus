defmodule Torus.Semantic.Embeddings.GeminiTest do
  @moduledoc false
  use Torus.Case, async: true

  test "generate/2" do
    Req.Test.stub(:req_plug, fn conn ->
      Req.Test.json(conn, %{
        "embeddings" => [
          %{
            "values" => [-0.023962751, 0.009122589, -0.06148394]
          },
          %{
            "values" => [-0.04984722, -0.02425884, -0.09362393]
          }
        ]
      })
    end)

    Application.put_env(:torus, Torus.Embeddings.Gemini, token: "token")

    terms = ["Hello world", "Elixir is great"]

    # This cryptic binary data corresponds to vectorized embeddings
    assert [
             %Pgvector{data: "\0\x03\0\0\xBC\xC4M\x88<\x15v\xE9\xBD{֕"},
             %Pgvector{data: "\0\x03\0\0\xBDL,\x99\xBCƺz\xBD\xBF\xBD\xE7"}
           ] = Torus.Embeddings.Gemini.generate(terms)
  end
end
