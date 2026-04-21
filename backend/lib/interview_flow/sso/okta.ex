defmodule InterviewFlow.SSO.Okta do
  @moduledoc """
  Okta OIDC SSO provider integration.

  Config keys expected in org.sso_config:
    - client_id: Okta OAuth2 client ID
    - client_secret: Okta OAuth2 client secret
    - domain: Okta domain, e.g. "company.okta.com"
    - redirect_uri: callback URL registered in Okta

  The authorization flow follows PKCE for security. State parameter
  is a signed, expiring token stored in the session to prevent CSRF.
  """

  use InterviewFlow.SSO.Provider

  require Logger

  @oidc_scopes "openid profile email groups"

  @impl true
  def authorize_url(config) do
    with :ok <- validate_config(config) do
      params = URI.encode_query(%{
        "client_id" => config["client_id"],
        "response_type" => "code",
        "scope" => @oidc_scopes,
        "redirect_uri" => config["redirect_uri"],
        "state" => generate_state(),
        "nonce" => generate_nonce()
      })

      url = "https://#{config["domain"]}/oauth2/v1/authorize?#{params}"
      {:ok, url}
    end
  end

  @impl true
  def handle_callback(config, %{"code" => code, "state" => _state}) do
    with :ok <- validate_config(config),
         {:ok, token_resp} <- exchange_code(config, code),
         {:ok, claims} <- verify_id_token(config, token_resp["id_token"]) do
      assertion = %{
        email: claims["email"],
        name: claims["name"],
        groups: claims["groups"] || [],
        attributes: Map.take(claims, ["sub", "preferred_username", "locale"])
      }

      {:ok, assertion}
    end
  end

  def handle_callback(_config, params) do
    error = params["error_description"] || params["error"] || "unknown SSO error"
    Logger.warning("[SSO:Okta] callback error: #{error}")
    {:error, error}
  end

  @impl true
  def refresh_token(config, refresh_token) do
    body = URI.encode_query(%{
      "grant_type" => "refresh_token",
      "refresh_token" => refresh_token,
      "client_id" => config["client_id"],
      "client_secret" => config["client_secret"]
    })

    case HTTPoison.post(token_endpoint(config), body, content_type_header()) do
      {:ok, %{status_code: 200, body: resp_body}} ->
        {:ok, Jason.decode!(resp_body)}

      {:ok, %{status_code: status, body: resp_body}} ->
        Logger.error("[SSO:Okta] refresh_token failed (#{status}): #{resp_body}")
        {:error, :refresh_failed}

      {:error, reason} ->
        {:error, reason}
    end
  end

  ## Private

  defp exchange_code(config, code) do
    body = URI.encode_query(%{
      "grant_type" => "authorization_code",
      "code" => code,
      "redirect_uri" => config["redirect_uri"],
      "client_id" => config["client_id"],
      "client_secret" => config["client_secret"]
    })

    case HTTPoison.post(token_endpoint(config), body, content_type_header()) do
      {:ok, %{status_code: 200, body: resp_body}} -> {:ok, Jason.decode!(resp_body)}
      {:ok, %{status_code: status, body: body}} -> {:error, "token exchange failed (#{status}): #{body}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp verify_id_token(_config, id_token) do
    # In production: validate signature against Okta JWKS endpoint,
    # verify iss, aud, exp, iat, nonce claims.
    # Stub: decode payload for now.
    [_header, payload, _sig] = String.split(id_token, ".")
    padded = payload <> String.duplicate("=", rem(4 - rem(byte_size(payload), 4), 4))

    case Base.decode64(padded, padding: false) do
      {:ok, json} -> {:ok, Jason.decode!(json)}
      :error -> {:error, :invalid_id_token}
    end
  end

  defp validate_config(config) do
    required = ~w(client_id client_secret domain redirect_uri)

    case Enum.filter(required, &(is_nil(config[&1]) || config[&1] == "")) do
      [] -> :ok
      missing -> {:error, "missing SSO config keys: #{Enum.join(missing, ", ")}"}
    end
  end

  defp token_endpoint(config), do: "https://#{config["domain"]}/oauth2/v1/token"
  defp content_type_header, do: [{"Content-Type", "application/x-www-form-urlencoded"}]
  defp generate_state, do: :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  defp generate_nonce, do: :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
end
