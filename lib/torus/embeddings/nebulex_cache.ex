if Code.ensure_loaded?(Nebulex) and Code.ensure_loaded(Decorator.Decorate) do
  defmodule Torus.Embeddings.NebulexCache do
    @moduledoc """
    Caching layer for the embedding module.

    A wrapper around [Nebulex](https://hexdocs.pm/nebulex/Nebulex.html) cache. It allows you to cache the embedding calls in memory, so you save the resources/cost of calling the embedding module multiple times for the same input.

    To use it:

    - Add the following to your `config.exs`:

      ```elixir
      config :torus, cache: Torus.Embeddings.NebulexCache
      config :torus, Torus.Embeddings.NebulexCache,
        embedding_module: Torus.Embeddings.PostgresML
        cache: Nebulex.Cache,
        otp_name: :your_app,
        adapter: Nebulex.Adapters.Local,
        # Other adapter-specific options
        allocated_memory: 1_000_000_000, # 1GB

      # Embedding module specific options
      config :torus, Torus.Embeddings.PostgresML, repo: TorusExample.Repo
      ```

    - Add `nebulex` and `decorator` to your `mix.exs` dependencies:

      ```elixir
      def deps do
      [
        {:nebulex, ">= 0.0.0"},
        {:decorator, ">= 0.0.0"}
      ]
      end
      ```

    - Add `Torus.Embeddings.NebulexCache` to your supervision tree:

      ```elixir
      def start(_type, _args) do
        children = [
          Torus.Embeddings.NebulexCache
        ]

        opts = [strategy: :one_for_one, name: YourApp.Supervisor]
        Supervisor.start_link(children, opts)
      end
      ```

    See the [Nebulex documentation](https://hexdocs.pm/nebulex/Nebulex.html) for more information on how to configure the cache.

    And you're good to go now. As you can see, we can create a chain of embedding modules to compose the embedding process of our choice.
    Each of them should implement the `Torus.Embedding` behaviour, and we're good to go!
    """
    @adapter Application.compile_env(:torus, Torus.Embeddings.NebulexCache)[:adapter] ||
               Nebulex.Adapters.Local

    @otp_app Application.compile_env(:torus, Torus.Embeddings.NebulexCache)[:otp_app] || :torus

    use Nebulex.Cache,
      otp_app: @otp_app,
      adapter: @adapter

    use Nebulex.Caching

    import Torus.Embeddings.Common

    @behaviour Torus.Embedding

    @impl true
    def embedding_model(opts) do
      get_option!(opts, __MODULE__, :embedding_module).embedding_model
    end

    @impl true
    @decorate cacheable(cache: __MODULE__)
    def generate(terms, opts) do
      get_option!(opts, __MODULE__, :embedding_module).generate(terms, opts)
    end
  end
else
  defmodule Torus.Embeddings.NebulexCache do
    @moduledoc """
    This module provides a cache for storing and retrieving embeddings.

    See `https://hexdocs.pm/nebulex/Nebulex.html` for more info on how to customize the cache.
    """

    @error_message """
    You need to add `:nebulex` and `:decorator` to your dependencies in order to use the Nebulex cache.
    """

    @behaviour Torus.Embedding

    def embedding_model(_opts) do
      raise @error_message
    end

    def generate(_terms, _opts) do
      raise @error_message
    end
  end
end
