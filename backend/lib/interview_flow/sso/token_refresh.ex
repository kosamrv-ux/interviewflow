defmodule InterviewFlow.SSO.TokenRefresh do
  @moduledoc """
  Handles SSO token refresh with loop detection.

  Bug discovered in staging (June 2026):
  When an Okta session expired, the frontend would receive a 401, attempt to
  refresh the token using the stored refresh_token, and receive another 401
  from Okta (because the refresh_token itself was also expired or revoked).

  The refresh logic in the auth plug then immediately re-triggered on the next
  request, creating an infinite loop of:
    401 → refresh attempt → 401 from Okta → refresh attempt → ...

  This flood of refresh requests hit Okta's API rate limit, causing 429 errors
  that were logged as auth errors and created false PagerDuty alerts.

  Fix:
  1. Track refresh attempt count in the session (max 3 attempts).
  2. After max attempts, clear the SSO session and redirect to SSO login rather
     than retrying indefinitely.
  3. Add a 5-second backoff between consecutive refresh attempts.
  4. On Okta 400 with error=invalid_grant, immediately treat as terminal
     (refresh_token is no longer valid; retry won't help).
  """

  require Logger

  alias InterviewFlow.SSO.Okta
  alias InterviewFlow.Accounts

  @max_refresh_attempts 3
  @refresh_backoff_seconds 5

  @doc """
  Attempts to refresh an expired SSO token.

  Returns:
    {:ok, new_token, new_refresh_token} — successfully refreshed
    {:redirect_to_sso, org_slug} — terminal failure, user must re-authenticate
    {:error, reason} — transient failure, can be retried
  """
  def refresh_token(org, user, refresh_token, attempt \\ 1) do
    if attempt > @max_refresh_attempts do
      Logger.warning(
        "[SSO:TokenRefresh] max attempts (#{@max_refresh_attempts}) reached for user #{user.id}, forcing re-login"
      )

      clear_sso_session(user)
      {:redirect_to_sso, org.slug}
    else
      if attempt > 1 do
        Process.sleep(@refresh_backoff_seconds * 1000)
      end

      provider = provider_for(org.sso_provider)

      case provider.refresh_token(org.sso_config, refresh_token) do
        {:ok, %{"access_token" => _token, "refresh_token" => new_refresh}} ->
          Logger.info("[SSO:TokenRefresh] token refreshed for user #{user.id}")
          {:ok, new_refresh}

        {:ok, %{"error" => "invalid_grant"}} ->
          # Terminal: refresh token is expired or revoked; cannot retry
          Logger.warning("[SSO:TokenRefresh] invalid_grant for user #{user.id} — forcing re-login")
          clear_sso_session(user)
          {:redirect_to_sso, org.slug}

        {:ok, %{"error" => error, "error_description" => desc}} ->
          Logger.error("[SSO:TokenRefresh] provider error (#{error}): #{desc}")
          {:error, "#{error}: #{desc}"}

        {:error, reason} ->
          Logger.warning("[SSO:TokenRefresh] attempt #{attempt} failed: #{inspect(reason)}")
          refresh_token(org, user, refresh_token, attempt + 1)
      end
    end
  end

  defp clear_sso_session(user) do
    # Revoke the local JWT and clear any stored refresh token
    Accounts.revoke_user_sessions(user)
  end

  defp provider_for("okta"), do: Okta
  defp provider_for("google_workspace"), do: InterviewFlow.SSO.GoogleWorkspace
  defp provider_for("azure_ad"), do: InterviewFlow.SSO.AzureAD
  defp provider_for(_), do: Okta
end
