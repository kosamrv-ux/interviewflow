defmodule InterviewFlow.MixProject do
  use Mix.Project

  def project do
    [
      app: :interview_flow,
      version: "0.1.0",
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  def application do
    [
      mod: {InterviewFlow.Application, []},
      extra_applications: [:logger, :runtime_tools, :crypto]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Phoenix
      {:phoenix, "~> 1.7.14"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.11"},
      {:postgrex, "~> 0.17"},
      {:phoenix_live_view, "~> 0.20"},
      {:phoenix_live_dashboard, "~> 0.8"},
      {:plug_cowboy, "~> 2.7"},
      {:jason, "~> 1.4"},
      {:dns_cluster, "~> 0.1"},
      {:bandit, "~> 1.5"},

      # Auth
      {:guardian, "~> 2.3"},
      {:bcrypt_elixir, "~> 3.1"},
      {:comeonin, "~> 5.4"},

      # Background jobs
      {:oban, "~> 2.17"},

      # Redis / PubSub
      {:redix, "~> 1.4"},
      {:phoenix_pubsub_redis, "~> 3.0"},

      # HTTP client (for AI service + Twilio)
      {:tesla, "~> 1.10"},
      {:hackney, "~> 1.20"},

      # Encryption (PII fields)
      {:cloak_ecto, "~> 1.3"},

      # Rate limiting
      {:hammer, "~> 6.2"},
      {:hammer_backend_redis, "~> 6.1"},

      # Observability
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.1"},
      {:prom_ex, "~> 1.9"},
      {:sentry, "~> 10.2"},
      {:logger_json, "~> 6.1"},

      # Utilities
      {:uuid, "~> 1.1"},
      {:timex, "~> 3.7"},
      {:mime, "~> 2.0"},

      # Dev / Test
      {:excoveralls, "~> 0.18", only: :test},
      {:ex_machina, "~> 2.8", only: [:test, :dev]},
      {:faker, "~> 0.18", only: [:test, :dev]},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:phoenix_live_reload, "~> 1.5", only: :dev},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind default", "esbuild default"],
      "assets.deploy": [
        "tailwind default --minify",
        "esbuild default --minify",
        "phx.digest"
      ]
    ]
  end
end
