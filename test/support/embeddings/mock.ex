defmodule Torus.Test.Embeddings.Mock do
  @moduledoc false

  @vector Pgvector.new([
            0.1,
            0.2,
            0.3,
            0.4,
            0.5,
            0.6,
            0.7,
            0.8,
            0.9,
            1.0
          ])

  @behaviour Torus.Embedding
  def generate(_terms, _opts) do
    @vector
  end

  def embedding_model(_opts) do
    "tests/mock-model"
  end
end
