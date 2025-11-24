defmodule InterviewFlowWeb.Plugs.SetCurrentUser do
  @moduledoc """
  Plug that copies the Guardian-verified resource into `conn.assigns.current_user`.
  Must be used after `Guardian.Plug.LoadResource`.
  """

  import Plug.Conn
  alias InterviewFlow.Auth.Guardian

  def init(opts), do: opts

  def call(conn, _opts) do
    user = Guardian.Plug.current_resource(conn)

    if user do
      conn
      |> assign(:current_user, user)
    else
      conn
    end
  end
end
