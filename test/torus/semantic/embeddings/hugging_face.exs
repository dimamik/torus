defmodule Torus.Semantic.Embeddings.HuggingFace do
  @moduledoc false
  use Torus.Case, async: true

  test "generate/2" do
    Req.Test.stub(:req_plug, fn conn ->
      Req.Test.json(conn, [
        [-0.03447732701897621, 0.031023245304822922, 0.006734952796250582],
        [-0.0538337267935276, -0.08974937349557877, -8.872233447618783e-4]
      ])
    end)

    Application.put_env(:torus, Torus.Embeddings.HuggingFace, token: "token")

    terms = ["Hello world", "Elixir is great"]

    # This cryptic binary data corresponds to vectorized embeddings
    assert [
             %Pgvector{data: "\0\x03\0\0\xBD\r8\x19<\xFE$v;ܰ\xE1"},
             %Pgvector{data: "\0\x03\0\0\xBD\\\x80\xC1\xBD\xB7΅\xBAh\x94\x8D"}
           ] = Torus.Embeddings.HuggingFace.generate(terms)
  end
end
