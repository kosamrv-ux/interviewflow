defmodule InterviewFlowWeb.Plugs.OrgScope do
  @moduledoc """
  Plug that enforces organization-scoped resource access.

  Resolves the current organization from the authenticated user and
  assigns it to conn.assigns[:current_org]. All downstream controllers
  must use this org_id when querying resources to enforce tenant isolation.

  If the user has no organization (rare for admin-created accounts before
  onboarding), the request is halted with 403.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias InterviewFlow.Organizations

  def init(opts), do: opts

  def call(conn, _opts) do
    case conn.assigns[:current_user] do
      nil ->
        # Auth plug should have already halted; this is defensive
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "authentication required"})
        |> halt()

      user when is_nil(user.org_id) ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "no organization associated with this account"})
        |> halt()

      user ->
        org = Organizations.get_organization!(user.org_id)
        conn
        |> assign(:current_org, org)
        |> assign(:org_id, org.id)
        |> assign(:org_role, user.org_role)
    end
  end
end
