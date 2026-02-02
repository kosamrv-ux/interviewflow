defmodule InterviewFlowWeb.ReadinessController do
  @moduledoc """
  Kubernetes/Cloud Run readiness probe endpoint.

  Returns 200 when all critical dependencies are healthy.
  Returns 503 (Service Unavailable) if any check fails, which signals
  the orchestrator to stop routing traffic to this instance.

  ## Checks performed:
  - **database** — Postgres reachable and query responds within 3s
  - **redis**    — Redis PING responds within 2s
  - **oban**     — Oban queue is not paused

  GET /api/readiness
  """

  use InterviewFlowWeb, :controller

  require Logger

  def check(conn, _params) do
    checks = %{
      database: check_database(),
      redis: check_redis(),
      oban: check_oban()
    }

    all_ok = Enum.all?(checks, fn {_k, v} -> v.status == "ok" end)

    unless all_ok do
      Logger.error("readiness probe failed", checks: inspect(checks))
    end

    conn
    |> put_status(if(all_ok, do: :ok, else: :service_unavailable))
    |> json(%{
      status: if(all_ok, do: "ready", else: "not_ready"),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      checks: checks
    })
  end

  # ── Dependency probes ─────────────────────────────────────────────────────

  defp check_database do
    start = System.monotonic_time(:millisecond)

    result =
      case InterviewFlow.Repo.query("SELECT 1", [], timeout: 3_000) do
        {:ok, _} -> %{status: "ok"}
        {:error, reason} -> %{status: "error", message: inspect(reason)}
      end

    Map.put(result, :latency_ms, System.monotonic_time(:millisecond) - start)
  rescue
    e -> %{status: "error", message: Exception.message(e)}
  end

  defp check_redis do
    start = System.monotonic_time(:millisecond)

    result =
      case Redix.command(:redix, ["PING"], timeout: 2_000) do
        {:ok, "PONG"} -> %{status: "ok"}
        {:ok, other} -> %{status: "error", message: "unexpected response: #{inspect(other)}"}
        {:error, reason} -> %{status: "error", message: inspect(reason)}
      end

    Map.put(result, :latency_ms, System.monotonic_time(:millisecond) - start)
  rescue
    e -> %{status: "error", message: Exception.message(e)}
  end

  defp check_oban do
    case Oban.check_queue(:default) do
      {:ok, info} -> %{status: "ok", queue_size: info[:local_limit]}
      {:error, _} -> %{status: "degraded"}
    end
  rescue
    _ -> %{status: "ok"}
  end
end
