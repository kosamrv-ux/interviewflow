defmodule InterviewFlowWeb.Plugs.ApiKeyAuth do
  @moduledoc """
  Plug that authenticates requests via API key and updates last_used_at.

  Bug fix (May 2026):
  The `last_used_at` field on API keys was not being updated for v2 routes.
  This happened because the v2 router used a different pipeline that included
  this plug, but the plug was checking for a v1-specific header (`X-API-Key`)
  and silently falling through to the JWT auth path when using the v2
  `Authorization: Bearer if_live_...` header format.

  The Bearer prefix check was not distinguishing between JWT tokens (which
  start with `eyJ`) and API keys (which start with `if_live_` or `if_test_`).
  Both were passed to Guardian.decode_and_verify, which failed on API keys,
  returning a misleading "invalid token" error in logs.

  Fix: check the Bearer token prefix explicitly before deciding which
  authenticator to invoke. API keys always start with `if_` prefix.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias InterviewFlow.ApiKeys

  @api_key_prefix "if_"

  def init(opts), do: opts

  def call(conn, _opts) do
    case extract_bearer(conn) do
      {:api_key, raw_key} ->
        authenticate_api_key(conn, raw_key)

      {:jwt, _token} ->
        # Delegate to JWT auth — this plug only handles API keys
        conn

      :none ->
        conn
    end
  end

  defp authenticate_api_key(conn, raw_key) do
    case ApiKeys.authenticate(raw_key) do
      {:ok, api_key} ->
        conn
        |> assign(:api_key, api_key)
        |> assign(:org_id, api_key.org_id)
        |> assign(:auth_method, :api_key)
        |> assign(:api_scopes, api_key.scopes)

      :error ->
        conn
        |> put_status(:unauthorized)
        |> json(%{errors: [%{code: "invalid_api_key", message: "API key is invalid, expired, or revoked"}]})
        |> halt()
    end
  end

  defp extract_bearer(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] ->
        if String.starts_with?(token, @api_key_prefix) do
          {:api_key, token}
        else
          {:jwt, token}
        end

      _ ->
        # Also check legacy X-API-Key header for backward compat
        case get_req_header(conn, "x-api-key") do
          [key | _] -> {:api_key, key}
          [] -> :none
        end
    end
  end
end
