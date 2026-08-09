defmodule Torus.Semantic.Embeddings.NebulexCacheTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias Torus.Embeddings.NebulexCache

  defmodule CountingEmbedder do
    @moduledoc false
    @behaviour Torus.Embedding

    def generate(terms, opts) do
      send(opts[:test_pid], {:generated, terms})
      [Pgvector.new([1.0, 2.0])]
    end

    def embedding_model(_opts), do: "tests/counting-model"
  end

  test "caches embedding calls through the Nebulex local adapter" do
    start_supervised!(NebulexCache)

    opts = [embedding_module: CountingEmbedder, test_pid: self()]

    assert [%Pgvector{}] = NebulexCache.generate(["hello"], opts)
    assert_received {:generated, ["hello"]}

    assert [%Pgvector{}] = NebulexCache.generate(["hello"], opts)
    refute_received {:generated, ["hello"]}
  end
end
