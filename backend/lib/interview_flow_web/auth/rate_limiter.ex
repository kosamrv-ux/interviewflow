defmodule InterviewFlowWeb.Auth.RateLimiter do
  @moduledoc """
  Rate limiting for sensitive endpoints using Hammer + Redis.

  Limits:
  - auth_login: 10 attempts / minute per IP
  - auth_register: 5 attempts / minute per IP
  """

  @limits %{
    auth_login: {10, 60_000},
    auth_register: {5, 60_000}
  }

  def check(conn, action) do
    ip = get_client_ip(conn)
    {limit, window_ms} = Map.get(@limits, action, {100, 60_000})
    key = "rate_limit:#{action}:#{ip}"

    case Hammer.check_rate(key, window_ms, limit) do
      {:allow, _count} -> :ok
      {:deny, _limit} -> {:error, :rate_limited}
    end
  end

  defp get_client_ip(conn) do
    # Respect X-Forwarded-For from Cloud Run / load balancer
    case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
      [forwarded | _] -> forwarded |> String.split(",") |> List.first() |> String.trim()
      [] -> conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end
end
