defmodule InterviewFlowWeb.JobController do
  use InterviewFlowWeb, :controller

  alias InterviewFlow.Jobs
  alias InterviewFlow.Accounts

  @doc "GET /api/v1/jobs — Lists jobs for the current company."
  def index(conn, params) do
    company_id = conn.assigns.current_user.company_id

    opts = [
      status: params["status"],
      search: params["search"],
      after_cursor: params["after"],
      limit: parse_limit(params["limit"])
    ]

    {:ok, result} = Jobs.list_jobs(company_id, opts)

    conn
    |> put_status(:ok)
    |> json(%{
      data: Enum.map(result.data, &render_job/1),
      meta: result.meta
    })
  end

  @doc "POST /api/v1/jobs — Creates a new job."
  def create(conn, params) do
    user = conn.assigns.current_user

    unless Accounts.has_role?(user, ["admin", "recruiter"]) do
      conn
      |> put_status(:forbidden)
      |> json(%{errors: [%{message: "Only admins and recruiters can create jobs", code: "forbidden"}]})
    else
      case Jobs.create_job(user.company_id, user.id, params) do
        {:ok, job} ->
          conn
          |> put_status(:created)
          |> put_resp_header("location", "/api/v1/jobs/#{job.id}")
          |> json(render_job(job))

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{errors: format_errors(changeset)})
      end
    end
  end

  @doc "GET /api/v1/jobs/:id — Returns a job with pipeline stage counts."
  def show(conn, %{"id" => id}) do
    company_id = conn.assigns.current_user.company_id

    case Jobs.get_job_with_applications(company_id, id) do
      {:ok, job} ->
        stage_counts = Jobs.pipeline_stage_counts(job.id)

        conn
        |> put_status(:ok)
        |> json(Map.merge(render_job(job), %{stage_counts: stage_counts}))

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{errors: [%{message: "Job not found", code: "not_found"}]})
    end
  end

  @doc "PATCH /api/v1/jobs/:id — Updates a job."
  def update(conn, %{"id" => id} = params) do
    company_id = conn.assigns.current_user.company_id
    user = conn.assigns.current_user

    with {:ok, job} <- Jobs.get_job(company_id, id),
         :ok <- authorize_job_edit(user, job),
         {:ok, updated_job} <- Jobs.update_job(job, params) do
      conn
      |> put_status(:ok)
      |> json(render_job(updated_job))
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{errors: [%{message: "Job not found", code: "not_found"}]})

      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{errors: [%{message: "Forbidden", code: "forbidden"}]})

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
    end
  end

  @doc "POST /api/v1/jobs/:id/publish — Publishes a draft job."
  def publish(conn, %{"job_id" => id}) do
    company_id = conn.assigns.current_user.company_id

    with {:ok, job} <- Jobs.get_job(company_id, id),
         {:ok, published} <- Jobs.publish_job(job) do
      conn |> put_status(:ok) |> json(render_job(published))
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{errors: [%{message: "Job not found", code: "not_found"}]})

      {:error, :invalid_state_transition} ->
        conn
        |> put_status(:conflict)
        |> json(%{errors: [%{message: "Job must be in draft status to publish", code: "invalid_state"}]})
    end
  end

  @doc "POST /api/v1/jobs/:id/close — Closes a job to new applications."
  def close(conn, %{"job_id" => id}) do
    company_id = conn.assigns.current_user.company_id

    with {:ok, job} <- Jobs.get_job(company_id, id),
         {:ok, closed} <- Jobs.close_job(job) do
      conn |> put_status(:ok) |> json(render_job(closed))
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{errors: [%{message: "Job not found", code: "not_found"}]})

      {:error, :invalid_state_transition} ->
        conn
        |> put_status(:conflict)
        |> json(%{errors: [%{message: "Job must be open or paused to close", code: "invalid_state"}]})
    end
  end

  @doc "DELETE /api/v1/jobs/:id — Archives a job (soft delete)."
  def delete(conn, %{"id" => id}) do
    company_id = conn.assigns.current_user.company_id

    with {:ok, job} <- Jobs.get_job(company_id, id),
         {:ok, _} <- Jobs.archive_job(job) do
      send_resp(conn, :no_content, "")
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{errors: [%{message: "Job not found", code: "not_found"}]})
    end
  end

  # ─── Private helpers ─────────────────────────────────────────────────────

  defp authorize_job_edit(user, _job) do
    if Accounts.has_role?(user, ["admin", "recruiter"]) do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp parse_limit(nil), do: 25
  defp parse_limit(limit) when is_binary(limit), do: String.to_integer(limit)
  defp parse_limit(limit) when is_integer(limit), do: limit

  defp render_job(job) do
    %{
      id: job.id,
      title: job.title,
      department: job.department,
      location: job.location,
      remote_policy: job.remote_policy,
      employment_type: job.employment_type,
      description: job.description,
      requirements: job.requirements,
      salary_min: job.salary_min,
      salary_max: job.salary_max,
      salary_currency: job.salary_currency,
      pipeline_stages: job.pipeline_stages,
      status: job.status,
      company_id: job.company_id,
      created_by_id: job.created_by_id,
      published_at: job.published_at,
      closed_at: job.closed_at,
      inserted_at: job.inserted_at,
      updated_at: job.updated_at
    }
  end

  defp format_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.flat_map(fn {field, messages} ->
      Enum.map(messages, fn msg -> %{field: to_string(field), message: msg, code: "invalid"} end)
    end)
  end
end
