defmodule InterviewFlowWeb.HealthController do
  use InterviewFlowWeb, :controller

  alias InterviewFlow.Repo

  @doc """
  GET /api/health

  Returns 200 when the service is healthy.
  Checks database connectivity and returns version info.
  Used by Cloud Run health checks and the CI pipeline.
  """
  def check(conn, _params) do
    db_status = check_database()

    status = if db_status == :ok, do: "ok", else: "degraded"

    conn
    |> put_status(if status == "ok", do: :ok, else: :service_unavailable)
    |> json(%{
      status: status,
      version: Application.spec(:interview_flow, :vsn) |> to_string(),
      checks: %{
        database: db_status
      },
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end

  defp check_database do
    case Repo.query("SELECT 1", [], timeout: 3_000) do
      {:ok, _} -> "ok"
      {:error, reason} ->
        require Logger
        Logger.error("Health check DB failure: #{inspect(reason)}")
        "error"
    end
  rescue
    _ -> "error"
  end
end
