defmodule InterviewFlowWeb.SSOController do
  @moduledoc """
  Handles SSO login initiation and callback for enterprise organizations.

  Routes:
    GET  /auth/sso/:org_slug        — redirects to provider's authorize URL
    GET  /auth/sso/:org_slug/callback — handles provider callback, issues JWT
  """

  use InterviewFlowWeb, :controller

  alias InterviewFlow.Organizations
  alias InterviewFlow.Accounts
  alias InterviewFlowWeb.Auth.Guardian

  require Logger

  @provider_map %{
    "okta" => InterviewFlow.SSO.Okta,
    "google_workspace" => InterviewFlow.SSO.GoogleWorkspace,
    "azure_ad" => InterviewFlow.SSO.AzureAD,
    "saml_generic" => InterviewFlow.SSO.SAMLGeneric
  }

  def initiate(conn, %{"org_slug" => slug}) do
    with org when not is_nil(org) <- Organizations.get_organization_by_slug(slug),
         true <- org.sso_enabled,
         provider <- Map.get(@provider_map, org.sso_provider),
         {:ok, url} <- provider.authorize_url(org.sso_config) do
      conn
      |> put_session(:sso_org_id, org.id)
      |> redirect(external: url)
    else
      nil -> send_resp(conn, :not_found, "Organization not found")
      false -> send_resp(conn, :bad_request, "SSO is not enabled for this organization")
      {:error, reason} ->
        Logger.error("[SSO] initiate failed for #{slug}: #{inspect(reason)}")
        send_resp(conn, :internal_server_error, "SSO configuration error")
    end
  end

  def callback(conn, %{"org_slug" => slug} = params) do
    with org when not is_nil(org) <- Organizations.get_organization_by_slug(slug),
         true <- org.sso_enabled,
         provider <- Map.get(@provider_map, org.sso_provider),
         {:ok, assertion} <- provider.handle_callback(org.sso_config, params),
         {:ok, user} <- find_or_provision_user(org, assertion),
         {:ok, token, _claims} <- Guardian.encode_and_sign(user, %{org_id: org.id}) do
      json(conn, %{token: token, user: %{id: user.id, email: user.email, name: user.name}})
    else
      nil -> send_resp(conn, :not_found, "Organization not found")
      false -> send_resp(conn, :bad_request, "SSO is not enabled for this organization")
      {:error, reason} ->
        Logger.error("[SSO] callback failed for #{slug}: #{inspect(reason)}")
        conn |> put_status(:unauthorized) |> json(%{error: "SSO authentication failed"})
    end
  end

  defp find_or_provision_user(org, %{email: email, name: name}) do
    case Accounts.get_user_by_email(email) do
      nil ->
        Accounts.create_sso_user(%{
          email: email,
          name: name || String.split(email, "@") |> hd(),
          org_id: org.id,
          org_role: "member",
          password: :crypto.strong_rand_bytes(32) |> Base.encode64()
        })

      user ->
        if user.org_id == org.id do
          {:ok, user}
        else
          {:error, "user belongs to a different organization"}
        end
    end
  end
end
