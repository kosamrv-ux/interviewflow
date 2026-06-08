defmodule InterviewFlowWeb.Plugs.WebhookSignatureVerifier do
  @moduledoc """
  Plug that verifies HMAC-SHA256 signatures on outgoing webhook deliveries.

  Bug fixed (June 2026):
  Webhook signature verification was failing for payloads from certain
  integration partners (including Greenhouse) that send `application/x-www-form-urlencoded`
  rather than `application/json`.

  The issue: Plug.Conn.read_body/2 was called to get the raw body for signature
  verification. However, when the content-type was `application/x-www-form-urlencoded`,
  Phoenix's Endpoint had already consumed the body via `Plug.Parsers` before our
  plug ran, leaving `read_body/2` returning an empty string.

  The HMAC was computed against "" (empty string) instead of the actual body,
  so verification always failed for form-encoded payloads.

  Fix: store the raw request body in conn.assigns[:raw_body] using a custom
  body reader in the Endpoint configuration that caches the raw bytes before
  Plug.Parsers can consume them. This approach works for all content-types.

  See: `InterviewFlowWeb.Endpoint` — `plug Plug.Parsers, body_reader: ...`
  """

  import Plug.Conn

  require Logger

  @signature_header "x-interviewflow-signature"
  @timestamp_header "x-interviewflow-timestamp"
  @max_timestamp_skew_seconds 300

  def init(opts), do: opts

  def call(conn, _opts) do
    signature = get_req_header(conn, @signature_header) |> List.first()
    timestamp = get_req_header(conn, @timestamp_header) |> List.first()
    raw_body = conn.assigns[:raw_body] || ""

    cond do
      is_nil(signature) ->
        Logger.warning("[WebhookSig] missing signature header")
        reject(conn)

      is_nil(timestamp) ->
        Logger.warning("[WebhookSig] missing timestamp header")
        reject(conn)

      not valid_timestamp?(timestamp) ->
        Logger.warning("[WebhookSig] timestamp skew too large: #{timestamp}")
        reject(conn)

      not valid_signature?(raw_body, timestamp, signature) ->
        Logger.warning("[WebhookSig] signature mismatch")
        reject(conn)

      true ->
        conn
    end
  end

  defp valid_signature?(body, timestamp, "sha256=" <> sig) do
    secret = Application.get_env(:interview_flow, :webhook_signing_secret, "")
    # Include timestamp in the signed payload to prevent replay attacks
    signed_payload = "#{timestamp}.#{body}"
    expected = :crypto.mac(:hmac, :sha256, secret, signed_payload) |> Base.encode16(case: :lower)
    Plug.Crypto.secure_compare(expected, sig)
  end

  defp valid_signature?(_, _, _), do: false

  defp valid_timestamp?(timestamp_str) do
    case Integer.parse(timestamp_str) do
      {ts, ""} ->
        skew = abs(System.system_time(:second) - ts)
        skew <= @max_timestamp_skew_seconds

      _ ->
        false
    end
  end

  defp reject(conn) do
    conn
    |> send_resp(:unauthorized, Jason.encode!(%{error: "invalid webhook signature"}))
    |> halt()
  end
end
