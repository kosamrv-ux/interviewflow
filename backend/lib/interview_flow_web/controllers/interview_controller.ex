defmodule InterviewFlowWeb.InterviewController do
  use InterviewFlowWeb, :controller

  alias InterviewFlow.Interviews

  @doc "GET /api/v1/interviews/upcoming — Returns current user's upcoming interviews."
  def upcoming(conn, _params) do
    user_id = conn.assigns.current_user.id
    interviews = Interviews.list_upcoming(user_id)

    conn
    |> put_status(:ok)
    |> json(Enum.map(interviews, &render_interview/1))
  end

  @doc "GET /api/v1/interviews/:id"
  def show(conn, %{"id" => id}) do
    company_id = conn.assigns.current_user.company_id

    case Interviews.get_interview(company_id, id) do
      {:ok, interview} ->
        conn |> put_status(:ok) |> json(render_interview_detail(interview))

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{errors: [%{message: "Interview not found", code: "not_found"}]})
    end
  end

  @doc "POST /api/v1/interviews — Schedules a new interview."
  def create(conn, params) do
    user = conn.assigns.current_user

    attrs = Map.merge(params, %{"scheduled_by_id" => user.id})

    %InterviewFlow.Interviews.Interview{}
    |> InterviewFlow.Interviews.Interview.changeset(attrs)
    |> InterviewFlow.Repo.insert()
    |> case do
      {:ok, interview} ->
        conn
        |> put_status(:created)
        |> put_resp_header("location", "/api/v1/interviews/#{interview.id}")
        |> json(render_interview(interview))

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
    end
  end

  @doc "PATCH /api/v1/interviews/:id"
  def update(conn, %{"id" => id} = params) do
    company_id = conn.assigns.current_user.company_id

    with {:ok, interview} <- Interviews.get_interview(company_id, id),
         {:ok, updated} <-
           interview
           |> InterviewFlow.Interviews.Interview.changeset(params)
           |> InterviewFlow.Repo.update() do
      conn |> put_status(:ok) |> json(render_interview(updated))
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{errors: [%{message: "Interview not found", code: "not_found"}]})

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
    end
  end

  @doc "POST /api/v1/interviews/:id/cancel"
  def cancel(conn, %{"interview_id" => id, "reason" => reason}) do
    company_id = conn.assigns.current_user.company_id

    with {:ok, interview} <- Interviews.get_interview(company_id, id),
         {:ok, cancelled} <-
           interview
           |> InterviewFlow.Interviews.Interview.cancel_changeset(reason)
           |> InterviewFlow.Repo.update() do
      conn |> put_status(:ok) |> json(render_interview(cancelled))
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{errors: [%{message: "Interview not found", code: "not_found"}]})

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
    end
  end

  defp render_interview(interview) do
    %{
      id: interview.id,
      application_id: interview.application_id,
      title: interview.title,
      interview_type: interview.interview_type,
      scheduled_at: interview.scheduled_at,
      duration_minutes: interview.duration_minutes,
      timezone: interview.timezone,
      status: interview.status,
      cancelled_reason: interview.cancelled_reason,
      completed_at: interview.completed_at,
      inserted_at: interview.inserted_at
    }
  end

  defp render_interview_detail(interview) do
    base = render_interview(interview)

    Map.merge(base, %{
      video_sessions:
        if(Ecto.assoc_loaded?(interview.video_sessions),
          do: Enum.map(interview.video_sessions, &%{id: &1.id, status: &1.status, started_at: &1.started_at}),
          else: []
        )
    })
  end

  defp format_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", to_string(v)) end)
    end)
    |> Enum.flat_map(fn {f, msgs} -> Enum.map(msgs, &%{field: to_string(f), message: &1, code: "invalid"}) end)
  end
end
