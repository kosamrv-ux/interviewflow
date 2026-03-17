defmodule InterviewFlowWeb.Plugs.Cors do
  @moduledoc """
  Environment-specific CORS configuration.

  Allowed origins come from the ALLOWED_ORIGINS environment variable
  (comma-separated list), falling back to a compile-time default list.

  ## Production
  Origins: https://app.interviewflow.io, https://interviewflow.io

  ## Staging
  Origins: https://staging.interviewflow.io, https://preview.interviewflow.io

  ## Development
  Origins: http://localhost:5173, http://localhost:3000

  Credentials (cookies) are allowed for same-site session support.
  The WebRTC signaling endpoint (/signal/*) only allows same-origin requests.
  """

  import Plug.Conn

  @behaviour Plug

  @allowed_methods  ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
  @allowed_headers  [
    "authorization",
    "content-type",
    "accept",
    "x-request-id",
    "x-correlation-id",
    "sentry-trace",
    "baggage"
  ]
  @expose_headers   [
    "x-request-id",
    "x-correlation-id",
    "x-ratelimit-limit",
    "x-ratelimit-remaining",
    "x-ratelimit-reset",
    "x-pagination-page",
    "x-pagination-limit",
    "x-pagination-has-more"
  ]
  @max_age 7_200  # 2 hours

  def init(opts), do: opts

  def call(conn, _opts) do
    origin = get_req_header(conn, "origin") |> List.first()

    if is_nil(origin) do
      conn
    else
      handle_cors(conn, origin)
    end
  end

  defp handle_cors(conn, origin) do
    allowed_origins = allowed_origins()

    if origin in allowed_origins do
      conn
      |> put_resp_header("access-control-allow-origin",      origin)
      |> put_resp_header("access-control-allow-credentials", "true")
      |> put_resp_header("access-control-allow-methods",     Enum.join(@allowed_methods, ", "))
      |> put_resp_header("access-control-allow-headers",     Enum.join(@allowed_headers, ", "))
      |> put_resp_header("access-control-expose-headers",    Enum.join(@expose_headers, ", "))
      |> put_resp_header("access-control-max-age",           to_string(@max_age))
      |> put_resp_header("vary",                             "Origin")
      |> handle_preflight()
    else
      # Unknown origin — do not reflect origin, return without CORS headers
      # so the browser will block the request.
      conn
    end
  end

  defp handle_preflight(%{method: "OPTIONS"} = conn) do
    conn
    |> send_resp(:no_content, "")
    |> halt()
  end

  defp handle_preflight(conn), do: conn

  defp allowed_origins do
    case Application.get_env(:interview_flow, :allowed_origins) do
      nil ->
        default_origins()

      origins when is_list(origins) ->
        origins

      origins_str when is_binary(origins_str) ->
        origins_str
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
    end
  end

  defp default_origins do
    case Application.get_env(:interview_flow, :environment, :dev) do
      :prod ->
        [
          "https://app.interviewflow.io",
          "https://interviewflow.io"
        ]

      :staging ->
        [
          "https://staging.interviewflow.io",
          "https://preview.interviewflow.io"
        ]

      _ ->
        [
          "http://localhost:5173",
          "http://localhost:3000",
          "http://localhost:4000"
        ]
    end
  end
end
