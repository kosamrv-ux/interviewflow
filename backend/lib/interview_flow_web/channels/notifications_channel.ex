defmodule InterviewFlowWeb.NotificationsChannel do
  @moduledoc """
  Phoenix Channel for real-time in-app notifications.

  Clients subscribe to their personal notification stream after authentication.
  Events pushed over this channel:

  - `interview_reminder`   – upcoming interview alert (synced with email reminders)
  - `score_ready`          – AI score computation completed for an application
  - `application_advanced` – a candidate's stage changed
  - `invitation_accepted`  – a team invitation was accepted
  - `job_published`        – a draft job was published (relevant for recruiters)
  """

  use InterviewFlowWeb, :channel

  alias InterviewFlow.Accounts
  alias InterviewFlowWeb.Presence

  @impl true
  def join("notifications:" <> user_id, _params, socket) do
    if authorized?(socket, user_id) do
      send(self(), :after_join)
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_info(:after_join, socket) do
    {:ok, _} =
      Presence.track(socket, socket.assigns.current_user.id, %{
        online_at: System.system_time(:second),
        device: Map.get(socket.assigns, :device, "web")
      })

    push(socket, "presence_state", Presence.list(socket))
    {:noreply, socket}
  end

  @impl true
  def handle_in("mark_read", %{"notification_id" => _nid}, socket) do
    # Optimistic ACK – actual persistence handled by REST endpoint
    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("ping", _params, socket) do
    {:reply, {:ok, %{pong: true}}, socket}
  end

  @doc """
  Broadcasts a score_ready notification to all connections for the given user.
  Called by the scoring worker after persisting an AiScore.
  """
  def notify_score_ready(user_id, application_id, score) do
    InterviewFlowWeb.Endpoint.broadcast("notifications:#{user_id}", "score_ready", %{
      application_id: application_id,
      composite_score: score
    })
  end

  @doc "Broadcasts an interview_reminder to the target user."
  def notify_interview_reminder(user_id, interview_id, minutes_until) do
    InterviewFlowWeb.Endpoint.broadcast("notifications:#{user_id}", "interview_reminder", %{
      interview_id: interview_id,
      minutes_until: minutes_until
    })
  end

  @doc "Broadcasts a stage-advance event to all company subscribers."
  def notify_application_advanced(company_id, application_id, from_stage, to_stage) do
    InterviewFlowWeb.Endpoint.broadcast(
      "company:#{company_id}",
      "application_advanced",
      %{application_id: application_id, from: from_stage, to: to_stage}
    )
  end

  # ── Private ──────────────────────────────────────────────────────────────

  defp authorized?(socket, user_id) do
    socket.assigns[:current_user] &&
      to_string(socket.assigns.current_user.id) == user_id
  end
end
