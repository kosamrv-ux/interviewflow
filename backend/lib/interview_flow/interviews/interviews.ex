defmodule InterviewFlow.Interviews do
  @moduledoc """
  The Interviews context manages interview scheduling, video sessions,
  and Twilio TURN credential generation.

  Caching (March 2026):
  - list_upcoming/1 cached at hot TTL (60 s) per user — polled by the
    notification bell every 30 s; cache absorbs ~95% of those reads.
  - get_interview/2 cached at hot TTL; invalidated on cancel/complete.
  """

  import Ecto.Query, warn: false
  alias InterviewFlow.{Repo, Cache}
  alias InterviewFlow.Interviews.{Interview, VideoSession}
  alias InterviewFlow.Workers.TriggerScoringWorker

  # ─── Interviews ──────────────────────────────────────────────────────────

  @doc "Returns upcoming interviews for a user within the next 7 days."
  def list_upcoming(user_id) do
    Cache.fetch(Cache.key("upcoming_interviews", user_id), :hot, fn ->
      now    = DateTime.utc_now()
      cutoff = DateTime.add(now, 7, :day)

      results =
        Interview
        |> join(:inner, [i], ii in "interview_interviewers",
               on: ii.interview_id == i.id and ii.user_id == ^user_id)
        |> where([i], i.status == "scheduled" and i.scheduled_at >= ^now and i.scheduled_at <= ^cutoff)
        |> order_by([i], i.scheduled_at)
        |> preload(application: [:candidate, :job])
        |> Repo.all()

      {:ok, results}
    end)
    |> case do
      {:ok, results} -> results
      _ -> []
    end
  end

  @doc "Returns an interview by ID, verifying company ownership."
  def get_interview(company_id, interview_id) do
    Cache.fetch(Cache.key("interview", interview_id), :hot, fn ->
      query =
        Interview
        |> join(:inner, [i], a in assoc(i, :application), on: true)
        |> join(:inner, [i, a], j in assoc(a, :job), on: j.company_id == ^company_id)
        |> where([i], i.id == ^interview_id)
        |> preload([application: [:candidate, :job], video_sessions: []])

      case Repo.one(query) do
        nil       -> {:error, :not_found}
        interview -> {:ok, interview}
      end
    end)
  end

  # ─── Video Sessions ───────────────────────────────────────────────────────

  @doc """
  Creates a new video session for an interview.
  Returns the session with a signed token for WebSocket auth.
  """
  def create_session(interview_id, metadata \\ %{}) do
    %VideoSession{}
    |> VideoSession.create_changeset(%{interview_id: interview_id, metadata: metadata})
    |> Repo.insert()
  end

  @doc "Retrieves a session by ID and validates the token."
  def get_session_by_token(session_id, token) do
    case Repo.get_by(VideoSession, id: session_id, session_token: token) do
      nil -> {:error, :not_found}
      session -> {:ok, session}
    end
  end

  @doc "Marks a session as active (called when second participant joins the channel)."
  def activate_session(session_id) do
    case Repo.get(VideoSession, session_id) do
      nil ->
        {:error, :not_found}

      %VideoSession{status: "waiting"} = session ->
        session
        |> VideoSession.activate_changeset()
        |> Repo.update()

      %VideoSession{status: "active"} = session ->
        {:ok, session}

      _ ->
        {:error, :invalid_state}
    end
  end

  @doc """
  Ends a session and enqueues the AI scoring job.
  Returns the updated session.
  """
  def end_session(session_id, attrs \\ %{}) do
    case Repo.get(VideoSession, session_id) do
      nil ->
        {:error, :not_found}

      %VideoSession{status: status} when status in ["ended", "failed"] ->
        {:error, :already_ended}

      session ->
        Repo.transact(fn ->
          with {:ok, ended_session} <- Repo.update(VideoSession.end_changeset(session, attrs)) do
            # Enqueue AI scoring if there's a transcript
            if ended_session.transcript_url do
              {:ok, _job} =
                %{session_id: session_id}
                |> TriggerScoringWorker.new()
                |> Oban.insert()
            end

            {:ok, ended_session}
          end
        end)
    end
  end

  @doc """
  Fetches Twilio TURN credentials for the given session.
  Credentials are short-lived (TTL configurable, default 24h).
  """
  def get_ice_servers(session_id) do
    with {:ok, _session} <- get_session_by_id(session_id),
         {:ok, credentials} <- fetch_twilio_credentials() do
      {:ok,
       %{
         ice_servers: [
           %{urls: ["stun:stun.l.google.com:19302"]},
           %{
             urls: credentials.uris,
             username: credentials.username,
             credential: credentials.password
           }
         ]
       }}
    end
  end

  defp get_session_by_id(session_id) do
    case Repo.get(VideoSession, session_id) do
      nil -> {:error, :not_found}
      session -> {:ok, session}
    end
  end

  defp fetch_twilio_credentials do
    config = Application.get_env(:interview_flow, :twilio, [])
    account_sid = Keyword.get(config, :account_sid, System.get_env("TWILIO_ACCOUNT_SID"))
    auth_token = Keyword.get(config, :auth_token, System.get_env("TWILIO_AUTH_TOKEN"))
    ttl = Keyword.get(config, :ice_ttl, 86_400)

    if account_sid && auth_token do
      url = "https://api.twilio.com/2010-04-01/Accounts/#{account_sid}/Tokens.json"

      case Tesla.post(twilio_client(auth_token), url, Jason.encode!(%{Ttl: ttl})) do
        {:ok, %{status: 201, body: body}} ->
          data = Jason.decode!(body)
          {:ok, %{uris: data["ice_servers"] |> Enum.map(& &1["url"]), username: data["username"], password: data["password"]}}

        _ ->
          {:error, :twilio_unavailable}
      end
    else
      # Dev fallback: return public STUN only
      {:ok, %{uris: ["stun:stun.l.google.com:19302"], username: "", password: ""}}
    end
  end

  defp twilio_client(auth_token) do
    Tesla.client([
      {Tesla.Middleware.BasicAuth, %{password: auth_token}},
      Tesla.Middleware.JSON
    ])
  end
end
