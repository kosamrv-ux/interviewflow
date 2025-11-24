defmodule InterviewFlowWeb.Plugs.RequireRole do
  @moduledoc """
  Plug that enforces role-based access control on a set of routes.

  Usage:
      plug RequireRole, roles: ["admin"]
      plug RequireRole, roles: ["admin", "recruiter"]
  """

  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, opts) do
    allowed_roles = Keyword.fetch!(opts, :roles)
    user = conn.assigns[:current_user]

    if user && user.role in allowed_roles do
      conn
    else
      conn
      |> put_status(:forbidden)
      |> json(%{
        errors: [
          %{
            message: "You don't have permission to perform this action",
            code: "forbidden",
            required_roles: allowed_roles
          }
        ]
      })
      |> halt()
    end
  end
end
