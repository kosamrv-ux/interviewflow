defmodule InterviewFlowWeb.CandidateController do
  use InterviewFlowWeb, :controller

  alias InterviewFlow.Candidates

  @doc "GET /api/v1/candidates"
  def index(conn, params) do
    company_id = conn.assigns.current_user.company_id

    opts = [
      search: params["search"],
      tags: params["tags"] && String.split(params["tags"], ","),
      limit: params["limit"] && String.to_integer(params["limit"])
    ]

    {:ok, result} = Candidates.list_candidates(company_id, Keyword.filter(opts, fn {_k, v} -> v != nil end))

    conn
    |> put_status(:ok)
    |> json(%{data: Enum.map(result.data, &render_candidate/1), meta: result.meta})
  end

  @doc "GET /api/v1/candidates/:id"
  def show(conn, %{"id" => id}) do
    company_id = conn.assigns.current_user.company_id

    case Candidates.get_candidate_with_history(company_id, id) do
      {:ok, candidate} ->
        conn |> put_status(:ok) |> json(render_candidate_detail(candidate))

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{errors: [%{message: "Candidate not found", code: "not_found"}]})
    end
  end

  @doc "POST /api/v1/candidates — Creates a candidate manually (not via application form)."
  def create(conn, params) do
    company_id = conn.assigns.current_user.company_id
    attrs = Map.take(params, ["email", "full_name", "phone", "linkedin_url", "github_url",
                               "portfolio_url", "source", "notes", "tags"])

    case Candidates.upsert_candidate(company_id, attrs) do
      {:ok, candidate} ->
        conn
        |> put_status(:created)
        |> put_resp_header("location", "/api/v1/candidates/#{candidate.id}")
        |> json(render_candidate(candidate))

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
    end
  end

  @doc "PATCH /api/v1/candidates/:id"
  def update(conn, %{"id" => id} = params) do
    company_id = conn.assigns.current_user.company_id
    attrs = Map.take(params, ["full_name", "phone", "linkedin_url", "github_url",
                               "portfolio_url", "source", "notes", "tags"])

    with {:ok, candidate} <- Candidates.get_candidate(company_id, id),
         {:ok, updated} <- Candidates.update_candidate(candidate, attrs) do
      conn |> put_status(:ok) |> json(render_candidate(updated))
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{errors: [%{message: "Candidate not found", code: "not_found"}]})

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
    end
  end

  defp render_candidate(c) do
    %{
      id: c.id,
      email: c.email,
      full_name: c.full_name,
      phone: c.phone,
      linkedin_url: c.linkedin_url,
      github_url: c.github_url,
      portfolio_url: c.portfolio_url,
      resume_url: c.resume_url,
      source: c.source,
      tags: c.tags,
      notes: c.notes,
      company_id: c.company_id,
      inserted_at: c.inserted_at,
      updated_at: c.updated_at
    }
  end

  defp render_candidate_detail(c) do
    base = render_candidate(c)

    Map.merge(base, %{
      applications:
        if(Ecto.assoc_loaded?(c.applications),
          do: Enum.map(c.applications, &%{id: &1.id, job_id: &1.job_id, pipeline_stage: &1.pipeline_stage, status: &1.status, composite_score: &1.composite_score}),
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
