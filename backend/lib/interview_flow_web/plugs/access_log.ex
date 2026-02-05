defmodule InterviewFlowWeb.Plugs.AccessLog do
  @moduledoc """
  Emits a structured access log entry after each HTTP response.

  Combines timing, auth context, and response details into a single
  JSON log line. Designed to be placed after authentication plugs so
  that `current_user` is available in `conn.assigns`.

  Log format (fields always present):
    - `event`         — "http_access"
    - `method`        — GET | POST | ...
    - `path`          — request path (no query string)
    - `status`        — HTTP status code
    - `duration_ms`   — wall-clock time in milliseconds
    - `request_id`    — from RequestId plug
    - `correlation_id`— from CorrelationId plug
    - `user_id`       — nil if unauthenticated
    - `company_id`    — nil if unauthenticated
    - `ip`            — remote IP (respects X-Forwarded-For)
    - `user_agent`    — truncated to 200 chars
  """

  import Plug.Conn
  require Logger

  @ua_max 200

  def init(opts), do: opts

  def call(conn, _opts) do
    start = System.monotonic_time(:millisecond)

    register_before_send(conn, fn conn ->
      duration = System.monotonic_time(:millisecond) - start

      Logger.info("http_access",
        method: conn.method,
        path: conn.request_path,
        status: conn.status,
        duration_ms: duration,
        request_id: conn.assigns[:request_id],
        correlation_id: conn.assigns[:correlation_id],
        user_id: get_in(conn.assigns, [:current_user, :id]),
        company_id: get_in(conn.assigns, [:current_user, :company_id]),
        ip: remote_ip(conn),
        user_agent: user_agent(conn)
      )

      conn
    end)
  end

  defp remote_ip(conn) do
    case get_req_header(conn, "x-forwarded-for") do
      [forwarded | _] -> forwarded |> String.split(",") |> List.first() |> String.trim()
      [] -> to_string(:inet.ntoa(conn.remote_ip))
    end
  end

  defp user_agent(conn) do
    case get_req_header(conn, "user-agent") do
      [ua | _] -> String.slice(ua, 0, @ua_max)
      [] -> nil
    end
  end
end
