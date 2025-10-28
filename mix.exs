defmodule Torus.MixProject do
  use Mix.Project

  @version "0.5.2"
  @source_url "https://github.com/dimamik/torus"

  def project do
    [
      app: :torus,
      version: @version,
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      # Hex
      package: package(),
      description: """
      Torus bridges Ecto and PostgreSQL, simplifying building search queries.
      """,
      # Docs
      name: "Torus",
      docs: [
        main: "Torus",
        api_reference: false,
        source_ref: "v#{@version}",
        source_url: @source_url,
        extra_section: "GUIDES",
        groups_for_modules: groups_for_modules(),
        formatters: ["html"],
        extras: extras(),
        skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
      ]
    ]
  end

  def cli do
    [
      "ecto.migrate": :test,
      "ecto.reset": :test,
      "ecto.rollback": :test,
      "ecto.gen": :test,
      "test.ci": :test,
      "test.reset": :test,
      "test.setup": :test
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp groups_for_modules do
    [
      Embeddings: [~r/^Torus.Embedding/]
    ]
  end

  defp deps do
    [
      {:ecto, "~> 3.0"},
      {:ecto_sql, "~> 3.0"},
      {:pgvector, "~> 0.3"},
      {:postgrex, ">= 0.0.0"},
      {:bumblebee, ">= 0.0.0", optional: true},
      {:nebulex, ">= 0.0.0", optional: true},
      {:decorator, ">= 0.0.0", optional: true},
      {:nx, ">= 0.0.0", optional: true},
      {:req, ">= 0.0.0", optional: true},
      {:exla, ">= 0.0.0", optional: true},
      {:plug, "~> 1.0", only: [:test]},
      {:credo, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["Dima Mikielewicz"],
      licenses: ["MIT"],
      links: %{
        Website: "https://dimamik.com",
        Changelog: "#{@source_url}/blob/main/CHANGELOG.md",
        GitHub: @source_url
      },
      files: ~w(lib .formatter.exs mix.exs README* CHANGELOG* LICENSE*)
    ]
  end

  defp aliases do
    [
      release: [
        "cmd git tag v#{@version}",
        "cmd git push",
        "cmd git push --tags",
        "hex.publish --yes"
      ],
      "test.reset": ["ecto.drop --quiet", "test.setup"],
      "test.setup": ["ecto.create --quiet", "ecto.migrate --quiet"],
      "test.ci": [
        "format --check-formatted",
        "deps.unlock --check-unused",
        "credo --strict",
        "test --raise"
      ]
    ]
  end

  defp extras do
    [
      "guides/semantic_search.md",

      # TODO Add more guides
      "CHANGELOG.md": [title: "Changelog"]
    ]
  end
end
