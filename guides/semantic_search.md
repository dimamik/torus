# Semantic search

This guide will walk you through adding a semantic search to your application using `Torus` and PostgreSQL.

## Initial requirements

Your app needs to use PostgreSQL, Ecto, and you should be okay with storing and comparing embedded vectors in PostgreSQL.

## Getting started

Semantic search is a technology that understands the meaning behind words to deliver results that match a user's intent, not just exact keywords. It uses AI and machine learning to interpret natural language in context, improving the relevance of search results.

**An embedding** is a numerical representation (vector) of a word, sentence, or document in a high-dimensional space. It captures the semantic meaning of the text, allowing for more accurate comparisons and searches. The more dimensions the embedding has, the more information it can capture. However, higher dimensions also mean more complexity and computational cost.

## The process of a search splits into 3 phases:

1. Generate and store the embeddings for the data that you want to search.

   This can be done by `Torus.to_vectors/1` function. We'll get deeper into how we can do this efficiently later.

2. Generate an embedding for the search term.

   This will also be done by `Torus.to_vector/1` function.

3. Compare the embedding of the search term with the embeddings of the data that we want to search.

   This will be done by `Torus.similarity/5` function.

Overall, our search will look like this:

```elixir
def search(term) do
    # Generate embedding for the search term
    search_vector = Torus.to_vector(term)

    Post
    |> Torus.semantic([p], p.embedding, search_vector)
    |> Repo.all()
end
```

## 1. Generating embeddings

There are several ways to generate embeddings. `Torus` includes a set of built-in Torus.Embeddings modules that implement the Torus.Embedding behaviour—but you're not limited to those. You can easily implement the Torus.Embedding behaviour yourself — it’s designed to be simple and straightforward.

Here is what `Torus` provides out of the box:

### Torus.Embeddings.HuggingFace

`Torus.Embeddings.HuggingFace` is a wrapper around Hugging Face API. It allows you to generate embeddings using a variety of models available on Hugging Face.

To use it:

- Add the following to your `config.exs`:

  ```elixir
  config :torus, embedding_module: Torus.Embeddings.HuggingFace
  ```

- Add `req` to your `mix.exs` dependencies:

  ```elixir
  def deps do
  [
     {:req, "~> 0.5"}
  ]
  end
  ```

- Add an API token for hugging face to your `runtime.exs`. You can get your token [here](https://huggingface.co/settings/tokens).

  ```elixir
  config :torus, Torus.Embeddings.HuggingFace, token: System.get_env("HUGGING_FACE_API_KEY")
  ```

By default, it uses `sentence-transformers/all-MiniLM-L6-v2` model, but you can specify a different model by explicitly passing `model` to the config:

```elixir
config :torus, Torus.Embeddings.HuggingFace, model: "your/model"
```

### Torus.Embeddings.OpenAI

`Torus.Embeddings.OpenAI` is a wrapper around OpenAI API. It allows you to generate embeddings using OpenAI models.

To use it:

- Add the following to your `config.exs`:

  ```elixir
  config :torus, embedding_module: Torus.Embeddings.OpenAI
  ```

- Add `req` to your `mix.exs` dependencies:

  ```elixir
  def deps do
  [
     {:req, "~> 0.5"}
  ]
  end
  ```

- Add an API token for hugging face to your `runtime.exs`. You can get your token [here](https://huggingface.co/settings/tokens).

  ```elixir
  config :torus, Torus.Embeddings.OpenAI, token: System.get_env("OPEN_AI_API_KEY")
  ```

By default, it uses `sentence-transformers/all-MiniLM-L6-v2` model, but you can specify a different model by explicitly passing `model` to the config:

```elixir
config :torus, Torus.Embeddings.OpenAI, model: "your/model"
```

### Torus.Embeddings.PostgresML

`Torus.Embeddings.PostgresML` uses PostgreSQL [PostgresML extension](https://PostgresML.org/docs) to generate embeddings. It allows you to generate embeddings using a variety of models and performs inference directly in the database. This would require your database to have GPU support.

To use it, add the following to your `config.exs`:

```elixir
config :torus, embedding_module: Torus.Embeddings.PostgresML
config :torus, Torus.Embeddings.PostgresML, repo: YourApp.Repo
```

By default, it uses `sentence-transformers/all-MiniLM-L6-v2` model, but you can specify a different model by explicitly passing `model` to the config:

```elixir
config :torus, Torus.Embeddings.PostgresML, model: "your/model"
```

### Torus.Embeddings.LocalNxServing

`Torus.Embeddings.LocalNxServing` would probably require an instance with GPU support. It allows you to generate embeddings on your local machine using a variety of models available on Hugging Face. It leverages `nx` and `bumblebee` libraries to perform inference.

To use it:

- Add the following to your `config.exs`:

  ```elixir
  config :torus, embedding_module: Torus.Embeddings.LocalNxServing
  ```

- Add `bumblebee` and `nx` to your `mix.exs` dependencies:

  ```elixir
  def deps do
  [
     {:bumblebee, "~> 0.6"},
     {:nx, "~> 0.9"}
  ]
  end
  ```

- Add it to your supervision tree:

Here you'd probably want to start it only on machines with GPU. See more info in [Nx Serving documentation](https://hexdocs.pm/nx/Nx.Serving.html)

```elixir
def start(_type, _args) do
  children = [
    # Your deps
    Torus.Embeddings.LocalNxServing
  ]

  opts = [strategy: :one_for_one, name: YourApp.Supervisor]
  Supervisor.start_link(children, opts)
end
```

You can pass all options directly to `Nx.Serving.start_link/1` function by passing them to `Torus.Embeddings.LocalNxServing` when starting.

By default, it uses `sentence-transformers/all-MiniLM-L6-v2` model, but you can specify a different model by explicitly passing `model` to the config:

```elixir
config :torus, Torus.Embeddings.LocalNxServing, model: "your/model"
```

### Torus.Embeddings.Batcher

`Torus.Embeddings.Batcher`is a long‑running **GenServer** that collects individual embedding calls, groups them into a single batch, and forwards the
batch to the configured `embedding_module`. It can be used in pair with any of the above embedding modules.

It's considered a good practise to batch requests to the embedding module, especially when you are dealing with a high-traffic applications.

To use it:

- Add the following to your `config.exs`:

  ```elixir
   config :torus, batcher: Torus.Embeddings.Batcher

   config :torus, Torus.Embeddings.Batcher,
      max_batch_size: 10,
      default_batch_timeout: 100,
      embedding_module: Torus.Embeddings.HuggingFace
  ```

- Add it to your supervision tree:

  ```elixir
  def start(_type, _args) do
    children = [
      # Your deps
      Torus.Embeddings.Batcher
    ]

    opts = [strategy: :one_for_one, name: YourApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
  ```

- Configure your `embedding_module` of choice (see corresponding section)

And you should be good to call `Torus.to_vector/1` and `Torus.to_vectors/1` functions.

### Torus.Embeddings.NebulexCache

`Torus.Embeddings.NebulexCache` is a wrapper around [Nebulex](https://hexdocs.pm/nebulex/readme.html) cache. It allows you to cache the embedding calls in memory, so you save the resources/cost of calling the embedding module multiple times for the same input.

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

## 2. Storing the embeddings

### Database structure

There are multiple ways to store the embeddings, but I'd recommend going with the following approach:

```elixir
create table(:embeddings) do
   # model name as a string so that we can differentiate between different models
   add :model, :string, null: false
   # params used to generate the embedding/maybe version so we can filter by the newest later
   add :metadata, :jsonb, null: false, default: "{}"
   # TODO - Maybe more columns to differentiate this embedding from others
   # Actual embedding vector
   add :embedding, :vector, size: 384, null: false
end
```

```elixir
create table(:posts) do
   add :title, :string
   add :body, :string

   timestamps(type: :utc_datetime)
end
```

```elixir
create table(:post_embeddings) do
   add :post_id, references(:posts, on_delete: :delete_all), null: false
   add :embedding_id, references(:embeddings, on_delete: :delete_all), null: false
end
```

So we'd have a many to many relationship between posts and embeddings so we can version the embeddings and maybe have multiple embeddings for the same post. But I'd suggest concatenating all string/binary fields together to generate 1 embedding per 1 post for simplicity of the search later on.

### The embedding process - existing rows

I'd suggest inserting an [Oban](https://hexdocs.pm/oban/Oban.html) job to generate the embeddings in chunks for all rows in the database, using `Torus.to_vectors/1` function.

### The embedding process - new rows

<!-- TODO: Add oban job helper that can help the embedding process -->

There are a few ways to handle the embedding process for new rows:

1. Add a cron Oban job to run once in a while and embed in batches all needed rows.
2. Schedule an Oban job to embed the row after inserting it into the database.
3. (least recommended) Embed the row in the same transaction as inserting it into the database.

## 3. Searching

We'd need to generate the embedding and then compare it with the embeddings in the database. This can be done using `Torus.similarity/5` function.

```elixir
def search(term) do
  search_vector = Torus.to_vector(term)

  Post
  |> Torus.semantic([p], p.embedding, search_vector, distance: :l2_distance, pre_filter: 0.7)
  |> Repo.all()
end
```
