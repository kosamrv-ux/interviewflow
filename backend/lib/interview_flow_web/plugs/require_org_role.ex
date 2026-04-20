defmodule InterviewFlowWeb.Plugs.RequireOrgRole do
  @moduledoc """
  Plug that enforces a minimum organization role for a route.

  Usage in router:
    plug RequireOrgRole, :admin
    plug RequireOrgRole, :owner

  Role hierarchy (highest to lowest): owner > admin > member > viewer
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias InterviewFlow.Organizations

  def init(required_role), do: required_role

  def call(conn, required_role) do
    user = conn.assigns[:current_user]

    if user && Organizations.has_role?(user, required_role) do
      conn
    else
      conn
      |> put_status(:forbidden)
      |> json(%{error: "insufficient permissions", required_role: to_string(required_role)})
      |> halt()
    end
  end
end
