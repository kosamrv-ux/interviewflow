defmodule InterviewFlow.Jobs do
  @moduledoc """
  The Jobs context handles job posting lifecycle: creation, publishing,
  stage configuration, and search within a company.
  """

  import Ecto.Query, warn: false
  alias InterviewFlow.Repo
  alias InterviewFlow.Jobs.Job
  alias InterviewFlow.Candidates.Application

  @default_per_page 25

  @doc """
  Lists jobs for a company with optional filters.
  Returns `{:ok, %{data: [Job.t()], meta: map()}}`.
  """
  def list_jobs(company_id, opts \\ []) do
    status = Keyword.get(opts, :status)
    search = Keyword.get(opts, :search)
    after_cursor = Keyword.get(opts, :after_cursor)
    limit = min(Keyword.get(opts, :limit, @default_per_page), 100)

    base_query =
      Job
      |> where([j], j.company_id == ^company_id and is_nil(j.deleted_at))
      |> order_by([j], [desc: j.inserted_at])

    query =
      base_query
      |> maybe_filter_status(status)
      |> maybe_search(search)
      |> maybe_apply_cursor(after_cursor)
      |> limit(^(limit + 1))

    results = Repo.all(query)
    has_more = length(results) > limit
    data = Enum.take(results, limit)

    total =
      Job
      |> where([j], j.company_id == ^company_id and is_nil(j.deleted_at))
      |> maybe_filter_status(status)
      |> select(count())
      |> Repo.one()

    {:ok,
     %{
       data: data,
       meta: %{
         total: total,
         limit: limit,
         has_more: has_more,
         next_cursor: if(has_more, do: encode_cursor(List.last(data)), else: nil)
       }
     }}
  end

  @doc "Returns a job by ID, scoped to a company."
  def get_job(company_id, job_id) do
    case Repo.get_by(Job, id: job_id, company_id: company_id, deleted_at: nil) do
      nil -> {:error, :not_found}
      job -> {:ok, job}
    end
  end

  @doc "Returns a job with its applications preloaded."
  def get_job_with_applications(company_id, job_id) do
    case get_job(company_id, job_id) do
      {:ok, job} ->
        job = Repo.preload(job, applications: [:candidate, :ai_scores])
        {:ok, job}

      error ->
        error
    end
  end

  @doc "Creates a new job posting."
  def create_job(company_id, user_id, attrs) do
    attrs = Map.merge(attrs, %{"company_id" => company_id, "created_by_id" => user_id})

    %Job{}
    |> Job.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Updates a job's fields."
  def update_job(job, attrs) do
    job
    |> Job.changeset(attrs)
    |> Repo.update()
  end

  @doc "Publishes a draft job, making it visible for applications."
  def publish_job(job) do
    if job.status != "draft" do
      {:error, :invalid_state_transition}
    else
      job
      |> Job.publish_changeset()
      |> Repo.update()
    end
  end

  @doc "Closes a job to new applications."
  def close_job(job) do
    if job.status not in ["open", "paused"] do
      {:error, :invalid_state_transition}
    else
      job
      |> Job.close_changeset()
      |> Repo.update()
    end
  end

  @doc "Soft-deletes (archives) a job."
  def archive_job(job) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    job
    |> Ecto.Changeset.change(deleted_at: now, status: "archived")
    |> Repo.update()
  end

  @doc """
  Returns aggregate counts of applications per pipeline stage for a given job.
  Used to render the pipeline funnel on the dashboard.
  """
  def pipeline_stage_counts(job_id) do
    Application
    |> where([a], a.job_id == ^job_id and a.status == "active")
    |> group_by([a], a.pipeline_stage)
    |> select([a], {a.pipeline_stage, count(a.id)})
    |> Repo.all()
    |> Map.new()
  end

  # ─── Private helpers ──────────────────────────────────────────────────────

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: where(query, [j], j.status == ^status)

  defp maybe_search(query, nil), do: query
  defp maybe_search(query, ""), do: query

  defp maybe_search(query, search) do
    where(query, [j], fragment("? @@ plainto_tsquery('english', ?)", j.search_vector, ^search))
  end

  defp maybe_apply_cursor(query, nil), do: query

  defp maybe_apply_cursor(query, cursor) do
    case decode_cursor(cursor) do
      {:ok, %{inserted_at: ts, id: id}} ->
        where(
          query,
          [j],
          j.inserted_at < ^ts or (j.inserted_at == ^ts and j.id < ^id)
        )

      _ ->
        query
    end
  end

  defp encode_cursor(%Job{id: id, inserted_at: ts}) do
    %{id: id, inserted_at: ts}
    |> Jason.encode!()
    |> Base.url_encode64(padding: false)
  end

  defp decode_cursor(cursor) do
    with {:ok, json} <- Base.url_decode64(cursor, padding: false),
         {:ok, data} <- Jason.decode(json) do
      {:ok, %{id: data["id"], inserted_at: data["inserted_at"]}}
    else
      _ -> {:error, :invalid_cursor}
    end
  end
end
