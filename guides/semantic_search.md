# Semantic search

This guide will walk you through adding semantic search to your application using `Torus` and PostgreSQL.

## Initial requirements

Your app needs to use PostgreSQL and Ecto, and you should be comfortable storing and comparing embedded vectors in PostgreSQL.

## Getting started

Semantic search is a technology that understands the meaning behind words to deliver results that match a user's intent, not just exact keywords. It uses AI and machine learning to interpret natural language in context, improving the relevance of search results.

**An embedding** is a numerical representation (vector) of a word, sentence, or document in a high‑dimensional space. It captures the semantic meaning of the text, allowing for more accurate comparisons and searches. The more dimensions an embedding has, the more information it can capture. However, higher dimensions also mean greater complexity and computational cost.

## The search process is split into three phases:

1. Generate and store the embeddings for the data you want to search.

   We'll use `Torus.to_vectors/1` function. We'll dive deeper into how to do this efficiently later.

2. Generate an embedding for the search term.

   This is also done with the `Torus.to_vector/1` function.

3. Compare the embedding of the search term with the embeddings of the data you want to search.

   We'll do this using `Torus.semantic/5` function.

Overall, our search will look like this:

```elixir
def search(term) do
  # Generate an embedding for the search term
  search_vector = Torus.to_vector(term)

  Post
  |> Torus.semantic([p], p.embedding, search_vector)
  |> Repo.all()
end
```

Note: You’ll need to join or preload the associated embeddings if they're stored in a separate table.

## 1. Generating embeddings

There are several ways to generate embeddings. `Torus` includes a set of built‑in `Torus.Embeddings` modules that implement the `Torus.Embedding` behaviour - but you're not limited to those. You can easily implement the `Torus.Embedding` behaviour yourself — it’s designed to be simple and straightforward.

Here is what `Torus` provides out of the box:

### Torus.Embeddings.HuggingFace

`Torus.Embeddings.HuggingFace` is a wrapper around the Hugging Face API. It allows you to generate embeddings using a variety of models available on Hugging Face.

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

- Add an API token for Hugging Face to your `runtime.exs`. You can get your token [here](https://huggingface.co/settings/tokens).

  ```elixir
  config :torus, Torus.Embeddings.HuggingFace, token: System.get_env("HUGGING_FACE_API_KEY")
  ```

By default, it uses the `sentence-transformers/all-MiniLM-L6-v2` model, but you can specify a different model by explicitly passing `model` in the configuration:

```elixir
config :torus, Torus.Embeddings.HuggingFace, model: "your/model"
```

### Torus.Embeddings.OpenAI

`Torus.Embeddings.OpenAI` is a wrapper around the OpenAI API. It allows you to generate embeddings using OpenAI models.

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

- Add an API token for OpenAI to your `runtime.exs`. You can get your token [here](https://platform.openai.com/account/api-keys).

  ```elixir
  config :torus, Torus.Embeddings.OpenAI, token: System.get_env("OPEN_AI_API_KEY")
  ```

By default, it uses the `sentence-transformers/all-MiniLM-L6-v2` model, but you can specify a different model by explicitly passing `model` in the configuration:

```elixir
config :torus, Torus.Embeddings.OpenAI, model: "your/model"
```

### Torus.Embeddings.PostgresML

`Torus.Embeddings.PostgresML` uses the PostgreSQL [PostgresML extension](https://postgresml.org/docs) to generate embeddings. It allows you to generate embeddings using a variety of models and performs inference directly in the database. This requires your database to have GPU support.

To use it, add the following to your `config.exs`:

```elixir
config :torus, embedding_module: Torus.Embeddings.PostgresML
config :torus, Torus.Embeddings.PostgresML, repo: YourApp.Repo
```

By default, it uses the `sentence-transformers/all-MiniLM-L6-v2` model, but you can specify a different model by explicitly passing `model` in the configuration:

```elixir
config :torus, Torus.Embeddings.PostgresML, model: "your/model"
```

### Torus.Embeddings.LocalNxServing

`Torus.Embeddings.LocalNxServing` will probably require an instance with GPU support. It allows you to generate embeddings on your local machine using a variety of models available on Hugging Face. It leverages the `nx` and `bumblebee` libraries to perform inference.

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

  Here you'd probably want to start it only on machines with GPUs. See more information in the [Nx.Serving documentation](https://hexdocs.pm/nx/Nx.Serving.html).

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

You can pass all options directly to the `Nx.Serving.start_link/1` function by passing them to `Torus.Embeddings.LocalNxServing` when starting.

By default, it uses the `sentence-transformers/all-MiniLM-L6-v2` model, but you can specify a different model by explicitly passing `model` in the configuration:

```elixir
config :torus, Torus.Embeddings.LocalNxServing, model: "your/model"
```

### Torus.Embeddings.Batcher

`Torus.Embeddings.Batcher` is a long‑running **GenServer** that collects individual embedding calls, groups them into a single batch, and forwards the batch to the configured `embedding_module`. It can be used in combination with any of the embedding modules above.

It is considered good practice to batch requests to the embedding module, especially when you are dealing with high‑traffic applications.

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

- Configure your `embedding_module` of choice (see the corresponding section).

After that, you can call the `Torus.to_vector/1` and `Torus.to_vectors/1` functions.

### Torus.Embeddings.NebulexCache

`Torus.Embeddings.NebulexCache` is a wrapper around the [Nebulex](https://hexdocs.pm/nebulex/readme.html) cache. It allows you to cache embedding calls in memory, so you save resources and cost by avoiding repeated calls to the embedding module for the same input.

To use it:

- Add the following to your `config.exs`:

  ```elixir
  config :torus, cache: Torus.Embeddings.NebulexCache
  config :torus, Torus.Embeddings.NebulexCache,
    embedding_module: Torus.Embeddings.PostgresML,
    cache: Nebulex.Cache,
    otp_name: :your_app,
    adapter: Nebulex.Adapters.Local,
    # Other adapter‑specific options
    allocated_memory: 1_000_000_000 # 1 GB

  # Embedding‑module‑specific options
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

And you're good to go. As you can see, you can create a chain of embedding modules to compose an embedding process of your choice. Each of them should implement the `Torus.Embedding` behaviour, and you're all set!

## 2. Storing the embeddings

### Database structure

There are multiple ways to store embeddings, but I'd recommend the following approach:

```elixir
create table(:embeddings) do
  # Model name as a string so we can differentiate between models
  add :model, :string, null: false
  # Parameters used to generate the embedding (maybe an embedding version) so we can
  # filter by the newest later
  add :metadata, :jsonb, null: false, default: "{}"
  # Maybe more columns to differentiate this embedding from others?
  # Actual embedding vector (384 dimensions for the `all-MiniLM-L6-v2` model)
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

This gives us a many‑to‑many relationship between posts and embeddings, so we can version the embeddings and even store multiple embeddings for the same post. However, I'd suggest concatenating all string/binary fields together to generate one embedding per post for simpler searches later on.

There is also a pattern to store a vector without the dimensions and its dimensions and metadata in separate columns, but I'd not recommend it since we won't be able to [index this vector](https://tembo.io/blog/vector-indexes-in-pgvector) later on.

### The embedding process – existing rows

I suggest inserting an [Oban](https://hexdocs.pm/oban/Oban.html) job to generate embeddings in chunks for all rows in the database, using the `Torus.to_vectors/1` function.

### The embedding process – new rows

<!-- TODO: Add Oban job helper that can help the embedding process -->

There are a few ways to handle the embedding process for new rows:

1. Add a cron Oban job to run periodically and, in batches, embed all rows that need it.
2. Schedule an Oban job to embed the row after inserting it into the database.
3. (Least recommended) Embed the row in the same transaction used to insert it into the database.

## 3. Searching

We need to generate the embedding and then compare it with the embeddings in the database. This can be done using the `Torus.semantic/5` function.

```elixir
def search(term) do
  search_vector = Torus.to_vector(term)

  Post
  |> Torus.semantic([p], p.embedding, search_vector, distance: :l2_distance, pre_filter: 0.7)
  |> Repo.all()
end
```
