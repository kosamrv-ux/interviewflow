defmodule InterviewFlowWeb.Auth.ErrorHandler do
  @moduledoc "Guardian auth error handler — returns JSON 401 responses."

  import Plug.Conn
  import Phoenix.Controller

  @behaviour Guardian.Plug.ErrorHandler

  @impl true
  def auth_error(conn, {type, _reason}, _opts) do
    message =
      case type do
        :unauthenticated -> "Authentication required"
        :invalid_token -> "Invalid or expired token"
        :no_resource_found -> "Authenticated user not found"
        _ -> "Authentication failed"
      end

    conn
    |> put_status(:unauthorized)
    |> json(%{errors: [%{message: message, code: "unauthorized"}]})
    |> halt()
  end
end
