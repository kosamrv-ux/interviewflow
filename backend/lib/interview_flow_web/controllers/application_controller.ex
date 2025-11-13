defmodule InterviewFlowWeb.ApplicationController do
  use InterviewFlowWeb, :controller

  alias InterviewFlow.Candidates
  alias InterviewFlow.Jobs

  @doc """
  POST /api/v1/jobs/:job_id/apply

  Public endpoint — no authentication required.
  Creates or updates the candidate profile and submits an application.
  """
  def submit(conn, %{"job_id" => job_id} = params) do
    candidate_attrs = Map.take(params, ["email", "full_name", "phone", "linkedin_url",
                                        "github_url", "resume_url", "source", "cover_letter",
                                        "referral_name"])

    case Candidates.submit_application(job_id, candidate_attrs) do
      {:ok, {_job, candidate, application}} ->
        conn
        |> put_status(:created)
        |> json(%{
          id: application.id,
          status: application.status,
          pipeline_stage: application.pipeline_stage,
          applied_at: application.applied_at,
          candidate: %{
            id: candidate.id,
            email: candidate.email,
            full_name: candidate.full_name
          }
        })

      {:error, {:job_not_accepting, status}} ->
        conn
        |> put_status(:conflict)
        |> json(%{errors: [%{message: "This job is #{status} and not accepting applications", code: "job_closed"}]})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{errors: [%{message: "Job not found", code: "not_found"}]})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_errors(changeset)})
    end
  end

  @doc "GET /api/v1/applications — Lists applications with filters."
  def index(conn, params) do
    company_id = conn.assigns.current_user.company_id

    opts = [
      job_id: params["job_id"],
      pipeline_stage: params["stage"],
      assigned_to: params["assigned_to"],
      status: params["status"] || "active",
      limit: parse_limit(params["limit"])
    ]

    applications = Candidates.list_applications(company_id, opts)

    conn
    |> put_status(:ok)
    |> json(%{data: Enum.map(applications, &render_application/1)})
  end

  @doc "GET /api/v1/applications/:id — Returns an application with full context."
  def show(conn, %{"id" => id}) do
    company_id = conn.assigns.current_user.company_id

    case Candidates.get_application(company_id, id) do
      {:ok, application} ->
        conn |> put_status(:ok) |> json(render_application_detail(application))

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{errors: [%{message: "Application not found", code: "not_found"}]})
    end
  end

  @doc "PATCH /api/v1/applications/:id — Updates recruiter-side fields."
  def update(conn, %{"id" => id} = params) do
    company_id = conn.assigns.current_user.company_id

    with {:ok, application} <- Candidates.get_application(company_id, id),
         {:ok, updated} <- Candidates.update_application(application, params) do
      conn |> put_status(:ok) |> json(render_application(updated))
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{errors: [%{message: "Application not found", code: "not_found"}]})

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
    end
  end

  @doc "POST /api/v1/applications/:id/advance — Advances to next pipeline stage."
  def advance(conn, %{"id" => id, "stage" => new_stage}) do
    company_id = conn.assigns.current_user.company_id
    actor = conn.assigns.current_user

    with {:ok, application} <- Candidates.get_application(company_id, id),
         {:ok, updated} <- Candidates.advance_application(application, new_stage, actor) do
      conn |> put_status(:ok) |> json(render_application(updated))
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{errors: [%{message: "Application not found", code: "not_found"}]})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
    end
  end

  def advance(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{errors: [%{message: "stage is required", code: "bad_request"}]})
  end

  @doc "POST /api/v1/applications/:id/reject — Rejects with a reason."
  def reject(conn, %{"id" => id, "reason" => reason}) do
    company_id = conn.assigns.current_user.company_id
    actor = conn.assigns.current_user

    with {:ok, application} <- Candidates.get_application(company_id, id),
         {:ok, updated} <- Candidates.reject_application(application, reason, actor) do
      conn |> put_status(:ok) |> json(render_application(updated))
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{errors: [%{message: "Application not found", code: "not_found"}]})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
    end
  end

  @doc "POST /api/v1/applications/:id/hire — Marks as hired."
  def hire(conn, %{"id" => id}) do
    company_id = conn.assigns.current_user.company_id
    actor = conn.assigns.current_user

    with {:ok, application} <- Candidates.get_application(company_id, id),
         {:ok, updated} <- Candidates.hire_application(application, actor) do
      conn |> put_status(:ok) |> json(render_application(updated))
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{errors: [%{message: "Application not found", code: "not_found"}]})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
    end
  end

  # ─── Private helpers ─────────────────────────────────────────────────────

  defp render_application(app) do
    %{
      id: app.id,
      job_id: app.job_id,
      candidate_id: app.candidate_id,
      assigned_to_id: app.assigned_to_id,
      pipeline_stage: app.pipeline_stage,
      status: app.status,
      rejection_reason: app.rejection_reason,
      composite_score: app.composite_score,
      rank_within_job: app.rank_within_job,
      applied_at: app.applied_at,
      stage_changed_at: app.stage_changed_at,
      inserted_at: app.inserted_at
    }
  end

  defp render_application_detail(app) do
    base = render_application(app)

    Map.merge(base, %{
      candidate: if(Ecto.assoc_loaded?(app.candidate), do: render_candidate_summary(app.candidate)),
      job: if(Ecto.assoc_loaded?(app.job), do: %{id: app.job.id, title: app.job.title, pipeline_stages: app.job.pipeline_stages}),
      interviews: if(Ecto.assoc_loaded?(app.interviews), do: Enum.map(app.interviews, &render_interview_summary/1), else: []),
      latest_score: if(Ecto.assoc_loaded?(app.ai_scores) and app.ai_scores != [], do: render_score_summary(hd(app.ai_scores)))
    })
  end

  defp render_candidate_summary(candidate) do
    %{
      id: candidate.id,
      full_name: candidate.full_name,
      email: candidate.email,
      linkedin_url: candidate.linkedin_url,
      github_url: candidate.github_url,
      source: candidate.source,
      tags: candidate.tags
    }
  end

  defp render_interview_summary(interview) do
    %{
      id: interview.id,
      title: interview.title,
      interview_type: interview.interview_type,
      scheduled_at: interview.scheduled_at,
      status: interview.status,
      duration_minutes: interview.duration_minutes
    }
  end

  defp render_score_summary(score) do
    %{
      id: score.id,
      composite_score: score.composite_score,
      recommended_action: score.recommended_action,
      strengths: score.strengths,
      status: score.status
    }
  end

  defp parse_limit(nil), do: 25
  defp parse_limit(n) when is_binary(n), do: String.to_integer(n)
  defp parse_limit(n) when is_integer(n), do: n

  defp format_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.flat_map(fn {field, msgs} ->
      Enum.map(msgs, fn msg -> %{field: to_string(field), message: msg, code: "invalid"} end)
    end)
  end
end
