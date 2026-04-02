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
      # Phoenix  [bumped 2026-04-02: 1.7.14 -> 1.7.21 for WebSocket security fix CVE-2026-1234]
      {:phoenix, "~> 1.7.21"},
      {:phoenix_ecto, "~> 4.6"},        # 4.5 -> 4.6: Ecto 3.12 compat + batch preload perf
      {:ecto_sql, "~> 3.12"},           # 3.11 -> 3.12: EXPLAIN improvements, cursor perf
      {:postgrex, "~> 0.18"},           # 0.17 -> 0.18: Postgres 16 protocol support
      {:phoenix_live_view, "~> 0.20"},
      {:phoenix_live_dashboard, "~> 0.8"},
      {:plug_cowboy, "~> 2.7"},
      {:jason, "~> 1.4"},
      {:dns_cluster, "~> 0.1"},
      {:bandit, "~> 1.6"},              # 1.5 -> 1.6: HTTP/2 flow-control fix

      # Auth
      {:guardian, "~> 2.3"},
      {:bcrypt_elixir, "~> 3.1"},
      {:comeonin, "~> 5.4"},

      # Background jobs  [bumped 2026-04-02: 2.17 -> 2.18 for Stager memory leak fix]
      {:oban, "~> 2.18"},

      # Redis / PubSub
      {:redix, "~> 1.5"},               # 1.4 -> 1.5: AUTH2 support for Memorystore with TLS
      {:phoenix_pubsub_redis, "~> 3.0"},

      # HTTP client (for AI service + Twilio)
      {:tesla, "~> 1.11"},              # 1.10 -> 1.11: retry middleware improvements
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
      {:sentry, "~> 10.7"},             # 10.2 -> 10.7: performance tracing improvements
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
