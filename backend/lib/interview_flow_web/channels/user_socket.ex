defmodule InterviewFlowWeb.UserSocket do
  use Phoenix.Socket

  alias InterviewFlow.Auth.Guardian

  channel "interview:*", InterviewFlowWeb.InterviewChannel
  channel "dashboard:*", InterviewFlowWeb.DashboardChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case Guardian.resource_from_token(token) do
      {:ok, user, _claims} ->
        {:ok, assign(socket, :current_user, user)}

      {:error, reason} ->
        require Logger
        Logger.warning("WebSocket auth failed: #{inspect(reason)}")
        :error
    end
  end

  def connect(_params, _socket, _connect_info) do
    :error
  end

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.current_user.id}"
end
