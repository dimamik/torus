defmodule Torus.SemanticSearch do
  @moduledoc """
  This module handles embeddings generation via `to_vector/2` and `to_vectors/2` functions.
  """

  @doc """
  Takes a list of terms and embedding module's specific options and passes them to `embedding_module.generate/2` function.

  Configure `embedding_module` either in `config.exs`:

        config :torus, :embedding_module, Torus.Embeddings.HuggingFace

  or pass `embedding_module` as an option to `to_vectors/2` function. Options always
  have greater priority than the config.

  See embedding module's documentation for more info.
  """
  def to_vectors(terms, opts \\ []) do
    embedding_module =
      if opts[:embedding_module] do
        opts[:embedding_module]
      else
        Application.fetch_env!(:torus, :embedding_module)
      end

    terms = List.wrap(terms)

    if Code.ensure_loaded?(embedding_module) &&
         function_exported?(embedding_module, :generate, 2) do
      embedding_module.generate(terms, opts)
    else
      raise "`embedding_module` must implement the `Torus.Embedding` behaviour"
    end
  end

  @doc """
  Same as `to_vectors/2`, but returns the first vector from the list.
  """
  def to_vector(term, opts \\ []) do
    term |> to_vectors(opts) |> List.first()
  end

  @doc """
  Calls the specified embedding module's `embedding_model/1` function to retrieve the model name.

  Check `Torus.SemanticSearch` for more info on how to configure the embedding module.
  """
  def embedding_model(opts \\ []) do
    embedding_module =
      if opts[:embedding_module] do
        opts[:embedding_module]
      else
        Application.fetch_env!(:torus, :embedding_module)
      end

    if Code.ensure_loaded?(embedding_module) &&
         function_exported?(embedding_module, :embedding_model, 1) do
      embedding_module.embedding_model(opts)
    else
      raise "`embedding_module` must implement the `Torus.Embedding` behaviour"
    end
  end
end
