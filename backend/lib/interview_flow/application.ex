defmodule InterviewFlow.Application do
  @moduledoc """
  Main OTP application — starts all supervision trees.

  Supervision tree (additions from March 2026 marked with *):

    InterviewFlow.Application
    ├── InterviewFlow.Repo
    ├── {DNSCluster, ...}
    ├── {Phoenix.PubSub, :interview_flow_pubsub}
    ├── {Redix, :redix_pool}*       — Redis pool for Cache, Hammer rate limiter
    ├── {Oban, oban_config()}       — background jobs (Oban 2.18)
    ├── {Task.Supervisor, ...}*     — async audit log writes
    ├── InterviewFlow.Telemetry
    └── InterviewFlowWeb.Endpoint

  Redix pool size: REDIS_POOL_SIZE env (default 5).
  Task.Supervisor allows fire-and-forget audit writes without blocking requests.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      InterviewFlow.Repo,
      {DNSCluster, query: Application.get_env(:interview_flow, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: InterviewFlow.PubSub},

      # Redis pool — shared by Cache module and Hammer rate limiting backend
      redix_spec(),

      # Background jobs (queues + plugins from QueueConfig)
      {Oban, oban_config()},

      # Task supervisor for fire-and-forget async operations
      {Task.Supervisor, name: InterviewFlow.TaskSupervisor},

      InterviewFlow.Telemetry,
      InterviewFlowWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: InterviewFlow.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    InterviewFlowWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # ── Oban ─────────────────────────────────────────────────────────────────

  defp oban_config do
    [
      repo:    InterviewFlow.Repo,
      queues:  InterviewFlow.Workers.QueueConfig.queues(),
      plugins: InterviewFlow.Workers.QueueConfig.plugins()
    ]
  end

  # ── Redix (Redis pool) ────────────────────────────────────────────────────

  defp redix_spec do
    redis_url = Application.get_env(:interview_flow, :redis_url,
      System.get_env("REDIS_URL", "redis://localhost:6379"))

    password = Application.get_env(:interview_flow, :redis_password,
      System.get_env("REDIS_PASSWORD"))

    opts = [name: :redix_pool, url: redis_url]
    opts = if password, do: Keyword.put(opts, :password, password), else: opts

    {Redix, opts}
  end
end
