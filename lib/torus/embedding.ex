defmodule Torus.Embedding do
  @moduledoc """
  Behaviour for generating embeddings for a list of terms.
  """

  @doc """
  Generates embeddings for a given list of terms.

  Should raise or retry on errors.
  """
  @callback generate(terms :: [binary()], opts :: keyword()) :: [%Pgvector{}]

  @doc """
  Returns a string representing the embedding model name `Torus` currently uses to generate embeddings.

  For example: `"sentence-transformers/paraphrase-MiniLM-L6-v2"`.
  """
  @callback embedding_model(opts :: keyword()) :: String.t()
end
