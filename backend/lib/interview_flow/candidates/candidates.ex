defmodule InterviewFlow.Candidates do
  @moduledoc """
  The Candidates context manages candidate profiles and their applications.
  """

  import Ecto.Query, warn: false
  alias InterviewFlow.Repo
  alias InterviewFlow.Candidates.{Candidate, Application}
  alias InterviewFlow.Jobs
  alias InterviewFlow.AuditLog

  @default_per_page 25

  # ─── Candidates ──────────────────────────────────────────────────────────

  @doc """
  Lists candidates for a company, with optional full-text search and tag filters.
  """
  def list_candidates(company_id, opts \\ []) do
    search = Keyword.get(opts, :search)
    tags = Keyword.get(opts, :tags, [])
    limit = min(Keyword.get(opts, :limit, @default_per_page), 100)
    after_cursor = Keyword.get(opts, :after_cursor)

    query =
      Candidate
      |> where([c], c.company_id == ^company_id and is_nil(c.deleted_at))
      |> order_by([c], [desc: c.inserted_at])
      |> maybe_search_candidates(search)
      |> maybe_filter_tags(tags)
      |> maybe_apply_cursor(after_cursor)
      |> limit(^(limit + 1))

    results = Repo.all(query)
    has_more = length(results) > limit
    data = Enum.take(results, limit)

    {:ok, %{data: data, meta: %{limit: limit, has_more: has_more}}}
  end

  @doc "Returns a candidate by ID, scoped to company."
  def get_candidate(company_id, candidate_id) do
    case Repo.get_by(Candidate, id: candidate_id, company_id: company_id) do
      nil -> {:error, :not_found}
      candidate -> {:ok, candidate}
    end
  end

  @doc "Returns a candidate with all their applications preloaded."
  def get_candidate_with_history(company_id, candidate_id) do
    case get_candidate(company_id, candidate_id) do
      {:ok, candidate} ->
        candidate =
          Repo.preload(candidate,
            applications: [
              job: [],
              interviews: [:video_sessions],
              ai_scores: []
            ]
          )

        {:ok, candidate}

      error ->
        error
    end
  end

  @doc "Creates or updates a candidate (upsert on company_id + email)."
  def upsert_candidate(company_id, attrs) do
    attrs = Map.put(attrs, "company_id", company_id)

    %Candidate{}
    |> Candidate.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:full_name, :phone, :linkedin_url, :github_url, :updated_at]},
      conflict_target: [:company_id, :email],
      returning: true
    )
  end

  @doc "Updates a candidate's profile fields."
  def update_candidate(candidate, attrs) do
    candidate
    |> Candidate.changeset(attrs)
    |> Repo.update()
  end

  # ─── Applications ────────────────────────────────────────────────────────

  @doc """
  Lists applications with compound filters.
  """
  def list_applications(company_id, opts \\ []) do
    job_id = Keyword.get(opts, :job_id)
    stage = Keyword.get(opts, :pipeline_stage)
    assigned_to = Keyword.get(opts, :assigned_to)
    status = Keyword.get(opts, :status, "active")
    limit = min(Keyword.get(opts, :limit, @default_per_page), 100)

    Application
    |> join(:inner, [a], j in assoc(a, :job), on: j.company_id == ^company_id)
    |> preload([:candidate, :assigned_to, :ai_scores])
    |> maybe_filter_job(job_id)
    |> maybe_filter_stage(stage)
    |> maybe_filter_assigned(assigned_to)
    |> where([a], a.status == ^status)
    |> order_by([a], [desc_nulls_last: a.composite_score, desc: a.applied_at])
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "Submits a public application (no auth; called from public job page)."
  def submit_application(job_id, candidate_attrs) do
    Repo.transact(fn ->
      with {:ok, job} <- Jobs.get_job_by_id(job_id),
           :ok <- validate_job_accepts_applications(job),
           {:ok, candidate} <- upsert_candidate(job.company_id, candidate_attrs),
           {:ok, application} <- create_application(job_id, candidate.id) do
        {:ok, {job, candidate, application}}
      end
    end)
  end

  defp create_application(job_id, candidate_id) do
    %Application{}
    |> Application.submission_changeset(%{job_id: job_id, candidate_id: candidate_id})
    |> Repo.insert()
  end

  @doc "Gets an application by ID, verifying company ownership."
  def get_application(company_id, application_id) do
    query =
      Application
      |> join(:inner, [a], j in assoc(a, :job), on: j.company_id == ^company_id)
      |> where([a], a.id == ^application_id)
      |> preload([:candidate, :job, :assigned_to, interviews: [:video_sessions], ai_scores: []])

    case Repo.one(query) do
      nil -> {:error, :not_found}
      application -> {:ok, application}
    end
  end

  @doc "Advances an application to the next pipeline stage."
  def advance_application(application, new_stage, actor) do
    with {:ok, job} <- Jobs.get_job(application.job.company_id, application.job_id) do
      changeset = Application.advance_changeset(application, new_stage, job)

      Repo.transact(fn ->
        with {:ok, updated} <- Repo.update(changeset) do
          AuditLog.log(job.company_id, actor.id, "application", application.id, "stage_changed", %{
            from: application.pipeline_stage,
            to: new_stage
          })

          {:ok, updated}
        end
      end)
    end
  end

  @doc "Rejects an application."
  def reject_application(application, reason, actor) do
    Repo.transact(fn ->
      with {:ok, updated} <- Repo.update(Application.reject_changeset(application, reason)) do
        AuditLog.log(application.job.company_id, actor.id, "application", application.id, "rejected", %{
          reason: reason
        })

        {:ok, updated}
      end
    end)
  end

  @doc "Marks an application as hired."
  def hire_application(application, actor) do
    Repo.transact(fn ->
      with {:ok, updated} <- Repo.update(Application.hire_changeset(application)) do
        AuditLog.log(application.job.company_id, actor.id, "application", application.id, "hired", %{})
        {:ok, updated}
      end
    end)
  end

  # ─── Private helpers ─────────────────────────────────────────────────────

  defp validate_job_accepts_applications(%{status: "open"}), do: :ok
  defp validate_job_accepts_applications(%{status: status}), do: {:error, {:job_not_accepting, status}}

  defp maybe_search_candidates(query, nil), do: query
  defp maybe_search_candidates(query, ""), do: query

  defp maybe_search_candidates(query, search) do
    where(query, [c], fragment("? @@ plainto_tsquery('english', ?)", c.search_vector, ^search))
  end

  defp maybe_filter_tags(query, []), do: query
  defp maybe_filter_tags(query, tags), do: where(query, [c], fragment("? @> ?", c.tags, ^tags))

  defp maybe_apply_cursor(query, nil), do: query

  defp maybe_apply_cursor(query, cursor) do
    case Base.url_decode64(cursor, padding: false) do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, %{"inserted_at" => ts, "id" => id}} ->
            where(query, [c], c.inserted_at < ^ts or (c.inserted_at == ^ts and c.id < ^id))

          _ ->
            query
        end

      _ ->
        query
    end
  end

  defp maybe_filter_job(query, nil), do: query
  defp maybe_filter_job(query, job_id), do: where(query, [a], a.job_id == ^job_id)

  defp maybe_filter_stage(query, nil), do: query
  defp maybe_filter_stage(query, stage), do: where(query, [a], a.pipeline_stage == ^stage)

  defp maybe_filter_assigned(query, nil), do: query
  defp maybe_filter_assigned(query, "me"), do: query
  defp maybe_filter_assigned(query, user_id), do: where(query, [a], a.assigned_to_id == ^user_id)
end
