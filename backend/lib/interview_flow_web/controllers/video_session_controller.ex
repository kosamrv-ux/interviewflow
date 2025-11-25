defmodule InterviewFlowWeb.VideoSessionController do
  use InterviewFlowWeb, :controller

  alias InterviewFlow.Interviews

  @doc "POST /api/v1/interviews/:interview_id/sessions — Creates a new video session."
  def create(conn, %{"interview_id" => interview_id}) do
    company_id = conn.assigns.current_user.company_id

    with {:ok, _interview} <- Interviews.get_interview(company_id, interview_id),
         {:ok, session} <- Interviews.create_session(interview_id) do
      conn
      |> put_status(:created)
      |> json(%{
        id: session.id,
        interview_id: session.interview_id,
        session_token: session.session_token,
        status: session.status,
        started_at: session.started_at,
        ended_at: session.ended_at,
        inserted_at: session.inserted_at
      })
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{errors: [%{message: "Interview not found", code: "not_found"}]})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_errors(changeset)})
    end
  end

  @doc "GET /api/v1/sessions/:id — Returns session status."
  def show(conn, %{"id" => session_id}) do
    case InterviewFlow.Repo.get(InterviewFlow.Interviews.VideoSession, session_id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{errors: [%{message: "Session not found", code: "not_found"}]})

      session ->
        conn
        |> put_status(:ok)
        |> json(%{
          id: session.id,
          interview_id: session.interview_id,
          status: session.status,
          started_at: session.started_at,
          ended_at: session.ended_at,
          duration_seconds: session.duration_seconds,
          participant_count: session.participant_count
        })
    end
  end

  @doc "GET /api/v1/sessions/:id/ice-servers — Returns Twilio TURN credentials."
  def ice_servers(conn, %{"id" => session_id}) do
    case Interviews.get_ice_servers(session_id) do
      {:ok, ice_config} ->
        conn |> put_status(:ok) |> json(ice_config)

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{errors: [%{message: "Session not found", code: "not_found"}]})

      {:error, :twilio_unavailable} ->
        # Fall back to public STUN only
        conn
        |> put_status(:ok)
        |> json(%{ice_servers: [%{urls: "stun:stun.l.google.com:19302"}]})
    end
  end

  @doc "POST /api/v1/sessions/:id/end — Ends a session and triggers AI scoring."
  def end_session(conn, %{"id" => session_id}) do
    case Interviews.end_session(session_id) do
      {:ok, session} ->
        conn
        |> put_status(:ok)
        |> json(%{
          id: session.id,
          status: session.status,
          ended_at: session.ended_at,
          duration_seconds: session.duration_seconds
        })

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{errors: [%{message: "Session not found", code: "not_found"}]})

      {:error, :already_ended} ->
        conn |> put_status(:conflict) |> json(%{errors: [%{message: "Session already ended", code: "conflict"}]})
    end
  end

  defp format_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", to_string(v)) end)
    end)
    |> Enum.flat_map(fn {f, msgs} -> Enum.map(msgs, &%{field: to_string(f), message: &1, code: "invalid"}) end)
  end
end
