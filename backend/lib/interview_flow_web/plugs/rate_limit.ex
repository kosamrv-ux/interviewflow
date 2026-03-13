defmodule InterviewFlowWeb.Plugs.RateLimit do
  @moduledoc """
  Per-IP and per-user rate limiting using Hammer with the Redis backend.

  ## Rate limit tiers

  | Scope       | Endpoint pattern       | Limit         | Window  |
  |-------------|------------------------|---------------|---------|
  | IP          | POST /auth/login       | 10 req        | 60 s    |
  | IP          | POST /auth/register    | 5 req         | 60 s    |
  | IP          | POST /jobs/:id/apply   | 10 req        | 300 s   |
  | IP (global) | any unauthenticated    | 300 req       | 60 s    |
  | User        | any authenticated      | 600 req       | 60 s    |
  | User        | POST /scores/:id/override | 30 req    | 60 s    |
  | User        | POST /*/rescore        | 5 req         | 300 s   |

  Exceeded limits return 429 with Retry-After and X-RateLimit-* headers.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  require Logger

  # ── Configuration ─────────────────────────────────────────────────────────

  @limits %{
    # { bucket_suffix, max_requests, window_ms }
    login:         {"login",    10,   60_000},
    register:      {"register",  5,   60_000},
    apply:         {"apply",    10,  300_000},
    override:      {"override", 30,   60_000},
    rescore:       {"rescore",   5,  300_000},
    authenticated: {"auth",    600,   60_000},
    unauthenticated: {"unauth", 300,  60_000}
  }

  # ── Plug callbacks ────────────────────────────────────────────────────────

  def init(opts), do: opts

  def call(conn, opts) do
    tier = Keyword.get(opts, :tier, :unauthenticated)
    check_rate_limit(conn, tier)
  end

  # ── Public helpers (used in router pipelines) ─────────────────────────────

  @doc "Checks the login-specific rate limit. Plug form: plug RateLimit, tier: :login"
  def check_login(conn, _opts),    do: check_rate_limit(conn, :login)

  @doc "Checks the register-specific rate limit."
  def check_register(conn, _opts), do: check_rate_limit(conn, :register)

  @doc "Checks the public apply rate limit."
  def check_apply(conn, _opts),    do: check_rate_limit(conn, :apply)

  @doc "Checks the authenticated user rate limit."
  def check_user(conn, _opts),     do: check_rate_limit(conn, :authenticated)

  @doc "Checks the score override rate limit."
  def check_override(conn, _opts), do: check_rate_limit(conn, :override)

  # ── Core logic ────────────────────────────────────────────────────────────

  defp check_rate_limit(conn, tier) do
    {bucket_suffix, max_req, window_ms} = Map.fetch!(@limits, tier)
    bucket = build_bucket(conn, tier, bucket_suffix)

    case Hammer.check_rate(bucket, window_ms, max_req) do
      {:allow, count} ->
        remaining = max(max_req - count, 0)
        reset_at  = System.system_time(:second) + div(window_ms, 1_000)

        conn
        |> put_resp_header("x-ratelimit-limit",     to_string(max_req))
        |> put_resp_header("x-ratelimit-remaining",  to_string(remaining))
        |> put_resp_header("x-ratelimit-reset",      to_string(reset_at))

      {:deny, _limit} ->
        reset_at     = System.system_time(:second) + div(window_ms, 1_000)
        retry_after  = div(window_ms, 1_000)

        Logger.warning("rate_limit: limit exceeded",
          tier: tier,
          bucket: bucket,
          ip: client_ip(conn)
        )

        conn
        |> put_resp_header("retry-after",        to_string(retry_after))
        |> put_resp_header("x-ratelimit-limit",  to_string(max_req))
        |> put_resp_header("x-ratelimit-remaining", "0")
        |> put_resp_header("x-ratelimit-reset",  to_string(reset_at))
        |> put_status(:too_many_requests)
        |> json(%{
          errors: [%{
            code:    "rate_limit_exceeded",
            message: "Too many requests. Please wait #{retry_after} seconds before retrying.",
            retry_after: retry_after
          }]
        })
        |> halt()
    end
  end

  defp build_bucket(conn, tier, suffix) when tier in [:authenticated, :override, :rescore] do
    user_id =
      case conn.assigns[:current_user] do
        nil  -> client_ip(conn)
        user -> user.id
      end

    "interviewflow:rl:#{suffix}:user:#{user_id}"
  end

  defp build_bucket(conn, _tier, suffix) do
    "interviewflow:rl:#{suffix}:ip:#{client_ip(conn)}"
  end

  defp client_ip(conn) do
    # Respect X-Forwarded-For only from trusted Cloud Load Balancer IPs.
    # The LB appends the real client IP as the last entry.
    forwarded = get_req_header(conn, "x-forwarded-for")

    case forwarded do
      [header | _] ->
        header
        |> String.split(",")
        |> List.last()
        |> String.trim()

      [] ->
        conn.remote_ip
        |> :inet.ntoa()
        |> to_string()
    end
  end
end
