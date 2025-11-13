defmodule InterviewFlowWeb.InterviewChannel do
  @moduledoc """
  WebRTC signaling channel for live interview sessions.

  Each channel process manages signaling for one video session.
  Participants join via `interview:<session_id>` and exchange
  WebRTC SDP offers/answers and ICE candidates through this channel.

  Phoenix Presence is used to track who is in the room, enabling
  the recruiter UI to show "candidate is present" status before starting.
  """

  use InterviewFlowWeb, :channel
  alias InterviewFlowWeb.Presence
  alias InterviewFlow.Interviews

  require Logger

  @impl true
  def join("interview:" <> session_id, %{"token" => session_token}, socket) do
    case Interviews.get_session_by_token(session_id, session_token) do
      {:ok, session} ->
        if session.status in ["waiting", "active"] do
          socket =
            socket
            |> assign(:session_id, session_id)
            |> assign(:session, session)
            |> assign(:user_id, socket.assigns.current_user.id)

          send(self(), :after_join)
          {:ok, %{session_id: session_id}, socket}
        else
          {:error, %{reason: "session_#{session.status}"}}
        end

      {:error, :not_found} ->
        {:error, %{reason: "session_not_found"}}
    end
  end

  def join("interview:" <> _, _params, _socket) do
    {:error, %{reason: "session_token_required"}}
  end

  @impl true
  def handle_info(:after_join, socket) do
    {:ok, _} =
      Presence.track(socket, socket.assigns.user_id, %{
        user_id: socket.assigns.user_id,
        online_at: DateTime.utc_now() |> DateTime.to_unix(),
        role: socket.assigns.current_user.role
      })

    push(socket, "presence_state", Presence.list(socket))

    # If session is in waiting state and now has participants, activate it
    maybe_activate_session(socket)

    {:noreply, socket}
  end

  @doc """
  WebRTC: Offer SDP from caller (recruiter) → relay to all other participants.
  """
  @impl true
  def handle_in("webrtc:offer", %{"sdp" => sdp, "to" => target_user_id}, socket) do
    Logger.debug("WebRTC offer from #{socket.assigns.user_id} to #{target_user_id} in session #{socket.assigns.session_id}")

    broadcast_to_user(socket, target_user_id, "webrtc:offer", %{
      sdp: sdp,
      from: socket.assigns.user_id
    })

    {:noreply, socket}
  end

  @doc """
  WebRTC: Answer SDP from callee (candidate) → relay back to offerer.
  """
  def handle_in("webrtc:answer", %{"sdp" => sdp, "to" => target_user_id}, socket) do
    broadcast_to_user(socket, target_user_id, "webrtc:answer", %{
      sdp: sdp,
      from: socket.assigns.user_id
    })

    {:noreply, socket}
  end

  @doc """
  WebRTC: ICE candidate trickle from either side.
  Broadcasts to all other participants in the session.
  """
  def handle_in("webrtc:ice_candidate", %{"candidate" => candidate}, socket) do
    broadcast_from!(socket, "webrtc:ice_candidate", %{
      candidate: candidate,
      from: socket.assigns.user_id
    })

    {:noreply, socket}
  end

  @doc """
  Chat message during the interview (not WebRTC, just channel relay).
  """
  def handle_in("chat:message", %{"text" => text}, socket) when byte_size(text) > 0 and byte_size(text) <= 2000 do
    broadcast!(socket, "chat:message", %{
      text: text,
      from: socket.assigns.user_id,
      timestamp: DateTime.utc_now() |> DateTime.to_unix(:millisecond)
    })

    {:noreply, socket}
  end

  @doc """
  Signals that a participant has muted their audio/video.
  Broadcast to all so the UI can show mute indicators.
  """
  def handle_in("media:state_changed", %{"audio" => audio, "video" => video}, socket) do
    broadcast_from!(socket, "media:state_changed", %{
      user_id: socket.assigns.user_id,
      audio: audio,
      video: video
    })

    {:noreply, socket}
  end

  @doc """
  Raised hand signal (candidate signals they want to speak).
  """
  def handle_in("participant:raised_hand", _params, socket) do
    broadcast!(socket, "participant:raised_hand", %{user_id: socket.assigns.user_id})
    {:noreply, socket}
  end

  # ─── Private helpers ─────────────────────────────────────────────────────

  defp maybe_activate_session(socket) do
    presence_count = Presence.list(socket) |> map_size()

    if presence_count >= 2 do
      case Interviews.activate_session(socket.assigns.session_id) do
        {:ok, _} ->
          broadcast!(socket, "session:started", %{
            session_id: socket.assigns.session_id,
            started_at: DateTime.utc_now() |> DateTime.to_unix()
          })

        _ ->
          :ok
      end
    end
  end

  # Sends a message to a specific user within this session's channel topic.
  # Since we can't target individual sockets directly, we use PubSub with a user-scoped topic.
  defp broadcast_to_user(socket, target_user_id, event, payload) do
    topic = "user:#{target_user_id}"
    InterviewFlowWeb.Endpoint.broadcast(topic, event, payload)

    # Also fan out via the session channel so monitoring tools can see it
    Logger.debug("Signaling #{event} → #{target_user_id}", session_id: socket.assigns.session_id)
  end
end
