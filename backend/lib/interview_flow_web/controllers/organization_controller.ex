defmodule InterviewFlowWeb.OrganizationController do
  use InterviewFlowWeb, :controller

  alias InterviewFlow.Organizations
  alias InterviewFlow.Organizations.Organization

  action_fallback InterviewFlowWeb.FallbackController

  def show(conn, _params) do
    org = conn.assigns.current_org
    render(conn, :show, organization: org)
  end

  def update(conn, %{"organization" => org_params}) do
    org = conn.assigns.current_org

    with {:ok, %Organization{} = updated} <- Organizations.update_organization(org, org_params) do
      render(conn, :show, organization: updated)
    end
  end

  def members(conn, _params) do
    org = conn.assigns.current_org
    members = Organizations.list_members(org)
    json(conn, %{data: members})
  end

  def remove_member(conn, %{"user_id" => user_id}) do
    org = conn.assigns.current_org
    user = InterviewFlow.Accounts.get_user!(user_id)

    with {:ok, _} <- Organizations.remove_member(org, user) do
      send_resp(conn, :no_content, "")
    else
      {:error, :last_owner} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "cannot remove the last owner of an organization"})
    end
  end

  def stats(conn, _params) do
    org = conn.assigns.current_org
    stats = Organizations.org_stats(org)
    json(conn, %{data: stats})
  end
end
