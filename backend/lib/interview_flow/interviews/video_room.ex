defmodule InterviewFlow.Interviews.VideoRoom do
  @moduledoc """
  Manages the lifecycle of a video interview room.

  Handles:
  - Room token generation for WebRTC signaling authentication
  - Recording start/stop tracking
  - Participant capacity enforcement (max 6 participants per room)
  - Room expiry (rooms expire 30 minutes after scheduled end time)
  """

  alias InterviewFlow.{Repo, Interviews}
  alias InterviewFlow.Interviews.{Interview, VideoSession}

  @max_participants 6
  @room_expiry_buffer_minutes 30
  @token_ttl_seconds 3600

  @doc """
  Opens (or returns) a video session for the given interview.

  Validates that the interview is in an appropriate state and that
  the requesting user is an authorized participant.
  """
  @spec open_room(Interview.t(), map()) ::
          {:ok, %{session: VideoSession.t(), room_token: String.t()}}
          | {:error, String.t()}
  def open_room(%Interview{status: status}, _user)
      when status in ["cancelled", "completed"],
      do: {:error, "interview is #{status} and cannot be joined"}

  def open_room(%Interview{} = interview, user) do
    with :ok <- check_participant_authorized(interview, user),
         {:ok, session} <- get_or_create_session(interview),
         :ok <- check_room_capacity(session),
         {:ok, token} <- generate_room_token(session, user) do
      {:ok, %{session: session, room_token: token}}
    end
  end

  @doc """
  Marks a video session as ended and triggers AI scoring.

  Called when the last participant leaves or the interviewer explicitly
  ends the session.
  """
  @spec close_room(VideoSession.t(), map()) :: {:ok, VideoSession.t()} | {:error, any()}
  def close_room(%VideoSession{} = session, %{id: user_id}) do
    Repo.transaction(fn ->
      {:ok, ended} =
        session
        |> VideoSession.end_changeset(%{ended_at: DateTime.utc_now(), ended_by: user_id})
        |> Repo.update()

      # Enqueue AI scoring job
      %{application_id: session.interview.application_id}
      |> InterviewFlow.Workers.TriggerScoringWorker.new(queue: :scoring)
      |> Oban.insert()

      ended
    end)
  end

  @doc "Returns room status including participant count and recording state."
  @spec room_status(VideoSession.t()) :: map()
  def room_status(%VideoSession{} = session) do
    %{
      session_id: session.id,
      status: session.status,
      participant_count: session.participant_count || 0,
      is_recording: session.recording_started_at != nil && session.recording_ended_at == nil,
      started_at: session.started_at,
      expires_at: room_expiry(session)
    }
  end

  @doc "Generates ICE server credentials (TURN/STUN configuration)."
  @spec ice_servers() :: [map()]
  def ice_servers do
    turn_secret = Application.get_env(:interview_flow, :turn_secret, "dev_secret")
    turn_host = Application.get_env(:interview_flow, :turn_host, "turn.interviewflow.io")
    ttl = @token_ttl_seconds

    username = "#{System.system_time(:second) + ttl}:interviewflow"

    credential =
      :crypto.mac(:hmac, :sha256, turn_secret, username)
      |> Base.encode64()

    [
      %{urls: ["stun:stun.l.google.com:19302"]},
      %{
        urls: ["turn:#{turn_host}:3478", "turns:#{turn_host}:5349"],
        username: username,
        credential: credential
      }
    ]
  end

  # ── Private helpers ──────────────────────────────────────────────────────

  defp check_participant_authorized(interview, user) do
    authorized_ids = [
      interview.interviewer_id,
      interview.application && interview.application.candidate_id
    ]

    if user.id in authorized_ids or user.role in ["admin", "recruiter"],
      do: :ok,
      else: {:error, "not authorized to join this room"}
  end

  defp get_or_create_session(interview) do
    case Interviews.get_active_session(interview.id) do
      nil -> Interviews.create_video_session(%{interview_id: interview.id})
      session -> {:ok, session}
    end
  end

  defp check_room_capacity(%VideoSession{participant_count: count}) when count >= @max_participants,
    do: {:error, "room is at capacity (max #{@max_participants} participants)"}

  defp check_room_capacity(_), do: :ok

  defp generate_room_token(%VideoSession{id: session_id}, %{id: user_id}) do
    token =
      %{session_id: session_id, user_id: user_id, exp: System.system_time(:second) + @token_ttl_seconds}
      |> Jason.encode!()
      |> Base.encode64()

    {:ok, token}
  end

  defp room_expiry(%VideoSession{interview: %{scheduled_at: at, duration_minutes: dur}}) do
    DateTime.add(at, (dur + @room_expiry_buffer_minutes) * 60, :second)
  end

  defp room_expiry(_), do: nil
end
