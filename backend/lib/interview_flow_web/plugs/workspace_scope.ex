defmodule InterviewFlowWeb.Plugs.WorkspaceScope do
  @moduledoc """
  Plug that scopes requests to the current user's workspace (organization).

  Extends OrgScope by providing workspace-level feature flag checks:
  - Enterprise-only features return 402 (payment required) for non-enterprise orgs
  - Beta features check the org's settings["beta_features"] list

  Applied to routes that have enterprise-gated endpoints.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  @enterprise_features ~w(sso webhook_delivery audit_log_export api_key_management)

  def init(opts), do: opts

  def call(conn, opts) do
    feature = Keyword.get(opts, :feature)

    if feature do
      check_feature_access(conn, to_string(feature))
    else
      conn
    end
  end

  defp check_feature_access(conn, feature) when feature in @enterprise_features do
    org = conn.assigns[:current_org]

    cond do
      is_nil(org) ->
        conn

      org.plan == "enterprise" ->
        conn

      feature_in_beta?(org, feature) ->
        conn

      true ->
        conn
        |> put_status(:payment_required)
        |> json(%{
          error: "enterprise_required",
          message: "The #{feature} feature requires an Enterprise plan.",
          upgrade_url: "https://interviewflow.io/pricing"
        })
        |> halt()
    end
  end

  defp check_feature_access(conn, _feature), do: conn

  defp feature_in_beta?(org, feature) do
    beta_features = get_in(org.settings, ["beta_features"]) || []
    feature in beta_features
  end
end
