defmodule InterviewFlowWeb.Plugs.SecurityHeaders do
  @moduledoc """
  Applies security-related HTTP response headers.

  Headers applied:

  | Header                        | Value (production)                                      |
  |-------------------------------|---------------------------------------------------------|
  | Content-Security-Policy       | strict-dynamic + nonce-based scripts                    |
  | Strict-Transport-Security     | max-age=63072000; includeSubDomains; preload             |
  | X-Frame-Options               | DENY                                                    |
  | X-Content-Type-Options        | nosniff                                                 |
  | Referrer-Policy               | strict-origin-when-cross-origin                         |
  | Permissions-Policy            | disable mic/cam/geolocation for non-video pages         |
  | X-XSS-Protection              | 0 (deprecated but some proxies still use it)            |
  | Cache-Control                 | no-store (API responses must not be cached by proxies)  |
  | X-Request-ID                  | propagated from CorrelationId plug                      |

  CSP nonce is generated per-request and injected as an assign so Phoenix
  templates can use it via `@csp_nonce`.
  """

  import Plug.Conn

  @behaviour Plug

  def init(opts), do: opts

  def call(conn, _opts) do
    nonce = generate_nonce()

    conn
    |> assign(:csp_nonce, nonce)
    |> put_resp_header("x-frame-options",           "DENY")
    |> put_resp_header("x-content-type-options",    "nosniff")
    |> put_resp_header("x-xss-protection",          "0")
    |> put_resp_header("referrer-policy",           "strict-origin-when-cross-origin")
    |> put_resp_header("cache-control",             "no-store")
    |> put_resp_header("strict-transport-security", hsts_header())
    |> put_resp_header("permissions-policy",        permissions_policy(conn))
    |> put_resp_header("content-security-policy",   csp_header(conn, nonce))
  end

  # ── HSTS ─────────────────────────────────────────────────────────────────

  defp hsts_header do
    # 2-year max-age; preload-eligible
    "max-age=63072000; includeSubDomains; preload"
  end

  # ── CSP ──────────────────────────────────────────────────────────────────

  defp csp_header(conn, nonce) do
    # Video session routes need media access; other routes get stricter policy.
    is_video = String.contains?(conn.request_path, "/sessions")

    directives = [
      "default-src 'self'",
      "script-src 'self' 'nonce-#{nonce}' 'strict-dynamic'",
      "style-src 'self' 'unsafe-inline'",   # Tailwind inline styles
      "img-src 'self' data: https://storage.googleapis.com",
      "font-src 'self'",
      "connect-src 'self' wss: https://api.sentry.io",
      # Only allow media capture on video session endpoints
      if(is_video, do: "media-src 'self' blob:", else: "media-src 'none'"),
      "object-src 'none'",
      "base-uri 'self'",
      "form-action 'self'",
      "frame-ancestors 'none'",
      "upgrade-insecure-requests",
      "block-all-mixed-content"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("; ")

    directives
  end

  # ── Permissions-Policy ────────────────────────────────────────────────────

  defp permissions_policy(conn) do
    is_video = String.contains?(conn.request_path, "/sessions")

    # Camera and mic allowed only on video session endpoints
    {camera, mic} =
      if is_video do
        {"camera=(self)", "microphone=(self)"}
      else
        {"camera=()", "microphone=()"}
      end

    [
      camera,
      mic,
      "geolocation=()",
      "payment=()",
      "usb=()",
      "interest-cohort=()"  # Opt out of FLoC/Topics API
    ]
    |> Enum.join(", ")
  end

  # ── Nonce ─────────────────────────────────────────────────────────────────

  defp generate_nonce do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end
end
