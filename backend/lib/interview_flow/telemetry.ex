defmodule InterviewFlow.Telemetry do
  @moduledoc """
  Sets up Telemetry metrics for InterviewFlow.

  Attaches handlers for:
  - Ecto query duration
  - Phoenix HTTP request duration
  - Phoenix Channel join/message latency
  - Oban job execution
  - Application-level business events (AI scoring, session lifecycle)

  Metrics are exported via telemetry_metrics_prometheus_core, scraped
  by a Prometheus sidecar in production. In development, they are
  logged via Logger at `:info` level every 30 seconds via
  `Telemetry.Metrics.ConsoleReporter`.
  """

  use Supervisor

  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children =
      if Application.get_env(:interview_flow, :env) == :prod do
        [
          {TelemetryMetricsPrometheus, metrics: metrics()}
        ]
      else
        [
          {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
        ]
      end

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp metrics do
    [
      # ---------- Phoenix HTTP ----------
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond},
        tags: [:route]
      ),
      counter("phoenix.router_dispatch.stop.duration",
        tags: [:route, :method],
        tag_values: &http_tag_values/1
      ),

      # ---------- Phoenix Channels ----------
      counter("phoenix.channel_joined.duration",
        tags: [:channel, :topic]
      ),
      summary("phoenix.channel_handled_in.duration",
        unit: {:native, :millisecond},
        tags: [:channel, :event]
      ),

      # ---------- Ecto ----------
      summary("interview_flow.repo.query.total_time",
        unit: {:native, :millisecond},
        tags: [:source, :command],
        tag_values: &ecto_tag_values/1,
        description: "Total wall-clock time for database queries"
      ),
      summary("interview_flow.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "Time spent waiting for a database connection"
      ),
      summary("interview_flow.repo.query.decode_time",
        unit: {:native, :millisecond},
        description: "Time spent decoding the database result"
      ),

      # ---------- Oban ----------
      counter("oban.job.start",
        tags: [:queue, :worker],
        description: "Number of Oban jobs started"
      ),
      summary("oban.job.stop.duration",
        unit: {:native, :millisecond},
        tags: [:queue, :worker, :state],
        description: "Oban job execution duration"
      ),
      counter("oban.job.exception",
        tags: [:queue, :worker, :kind],
        description: "Oban jobs that raised an exception"
      ),

      # Dead-letter tracking (added March 2026)
      counter("interview_flow.oban.dead_letter_alert",
        tags: [:queue, :priority],
        description: "PagerDuty alerts fired for Oban discard threshold"
      ),

      # ---------- Cache (added March 2026) ----------
      counter("interview_flow.cache.hit",
        tags: [:key_prefix],
        description: "Redis cache hits by key namespace prefix"
      ),
      counter("interview_flow.cache.miss",
        tags: [:key_prefix],
        description: "Redis cache misses (DB fallthrough triggered)"
      ),

      # ---------- Rate limiting (added March 2026) ----------
      counter("interview_flow.rate_limit.exceeded",
        tags: [:tier],
        description: "Rate limit threshold exceeded by tier"
      ),

      # ---------- Audit log (added March 2026) ----------
      counter("interview_flow.audit_log.archived",
        description: "Audit log rows archived to GCS cold storage"
      ),

      # ---------- Business events ----------
      counter("interview_flow.ai_scoring.requested",
        description: "Number of AI scoring requests dispatched"
      ),
      counter("interview_flow.ai_scoring.completed",
        tags: [:status],
        description: "AI scoring results (status: success | error)"
      ),
      summary("interview_flow.ai_scoring.duration_ms",
        description: "End-to-end AI scoring latency in milliseconds"
      ),
      counter("interview_flow.video_session.started",
        description: "Video sessions that reached the :active state"
      ),
      counter("interview_flow.video_session.ended",
        description: "Video sessions cleanly ended"
      ),
      summary("interview_flow.video_session.duration_seconds",
        description: "Duration of completed video sessions"
      ),
      counter("interview_flow.application.advanced",
        tags: [:from_stage, :to_stage],
        description: "Application pipeline stage transitions"
      ),
      counter("interview_flow.purge_sessions.completed",
        tags: [:status],
        description: "Sessions cleaned up by PurgeExpiredSessionsWorker"
      ),
    ]
  end

  defp http_tag_values(meta) do
    route =
      case meta[:route] do
        nil -> "unknown"
        r -> r
      end

    method =
      meta
      |> Map.get(:conn, %{})
      |> Map.get(:method, "unknown")

    %{route: route, method: method}
  end

  defp ecto_tag_values(meta) do
    %{
      source: meta[:source] || "unknown",
      command: meta[:result] |> elem_or(0, "unknown") |> to_string()
    }
  end

  defp elem_or(tuple, index, default) when is_tuple(tuple) do
    case elem(tuple, index) do
      nil -> default
      val -> val
    end
  rescue
    _ -> default
  end

  defp elem_or(_, _, default), do: default
end
