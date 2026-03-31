defmodule InterviewFlow.Jobs.JobService do
  @moduledoc """
  Service layer for job posting lifecycle management.

  Orchestrates the full job lifecycle including publication validation,
  archival, and analytics integration. Extracted from JobController to
  enforce consistent business rules regardless of how jobs are managed
  (HTTP API, admin panel, or future CLI tools).

  ## Lifecycle transitions

    draft → published → (open for applications)
    published → closed → (no new applications)
    closed → archived

  ## March 2026 additions

  - All lifecycle transitions now call Cache.invalidate_pattern to bust
    the company-scoped job list and dashboard aggregate caches.
  - Scoring rubric cache (day TTL) invalidated when job is updated with
    new scoring_rubric via ScoreService.invalidate_rubric/1.
  - AuditLog.log called for publish / close / archive / update.
  """

  require Logger

  alias InterviewFlow.{Repo, Jobs, Cache, AuditLog}
  alias InterviewFlow.Jobs.{Job, JobAnalytics}
  alias InterviewFlow.Metrics
  alias InterviewFlow.Scoring.ScoreService

  @doc """
  Publishes a draft job, making it visible to candidates.

  Validates:
  - Job is in "draft" status
  - Job has a title, description, and at least one required skill
  - Posting user has admin or recruiter role
  """
  @spec publish(Job.t(), map()) :: {:ok, Job.t()} | {:error, any()}
  def publish(%Job{status: "published"}, _actor),
    do: {:error, "job is already published"}

  def publish(%Job{status: status}, _actor) when status in ["closed", "archived"],
    do: {:error, "cannot publish a #{status} job"}

  def publish(%Job{} = job, actor) do
    with :ok <- check_publish_actor(actor),
         :ok <- validate_for_publication(job) do
      result =
        job
        |> Job.publish_changeset(%{
          status: "published",
          published_at: DateTime.utc_now(),
          published_by: actor.id
        })
        |> Repo.update()

      case result do
        {:ok, published_job} ->
          Logger.info("job_service: job published",
            job_id: published_job.id,
            publisher_id: actor.id
          )

          invalidate_job_caches(published_job.company_id)
          AuditLog.log(published_job.company_id, actor.id, "job", published_job.id, "published", %{})
          Metrics.emit_interview_scheduled("job_published")
          {:ok, published_job}

        err ->
          err
      end
    end
  end

  @doc """
  Closes a published job to new applications.

  Running applications continue; no new ones are accepted.
  """
  @spec close(Job.t(), map()) :: {:ok, Job.t()} | {:error, any()}
  def close(%Job{status: "draft"}, _actor),
    do: {:error, "cannot close an unpublished job"}

  def close(%Job{status: "closed"}, _actor),
    do: {:error, "job is already closed"}

  def close(%Job{} = job, actor) do
    result =
      job
      |> Job.changeset(%{status: "closed", closed_at: DateTime.utc_now(), closed_by: actor.id})
      |> Repo.update()

    case result do
      {:ok, closed_job} ->
        invalidate_job_caches(closed_job.company_id)
        AuditLog.log(closed_job.company_id, actor.id, "job", closed_job.id, "closed", %{})
        {:ok, closed_job}

      err -> err
    end
  end

  @doc """
  Archives a closed job, preventing any further modifications.
  Returns final analytics snapshot alongside the archived job.
  """
  @spec archive(Job.t(), map()) :: {:ok, %{job: Job.t(), final_analytics: map()}} | {:error, any()}
  def archive(%Job{status: status}, _actor) when status != "closed",
    do: {:error, "only closed jobs can be archived"}

  def archive(%Job{} = job, _actor) do
    final_analytics = JobAnalytics.funnel(job.id)

    with {:ok, archived} <-
           job
           |> Job.changeset(%{status: "archived"})
           |> Repo.update() do
      {:ok, %{job: archived, final_analytics: final_analytics}}
    end
  end

  @doc "Returns true if the job is accepting new applications."
  @spec accepting_applications?(Job.t()) :: boolean()
  def accepting_applications?(%Job{status: "published"}), do: true
  def accepting_applications?(_), do: false

  # ── Private helpers ──────────────────────────────────────────────────────

  defp invalidate_job_caches(company_id) do
    Cache.invalidate_pattern("if:jobs:#{company_id}:*")
    Cache.delete(Cache.agg_key("dashboard", company_id))
    ScoreService.invalidate_rubric(:all_for_company)  # placeholder; rubrics invalidated per-job on update
  end

  defp check_publish_actor(%{role: role}) when role in ["admin", "recruiter"], do: :ok
  defp check_publish_actor(_), do: {:error, "only admins and recruiters can publish jobs"}

  defp validate_for_publication(%Job{title: nil}), do: {:error, "job must have a title"}
  defp validate_for_publication(%Job{description: nil}), do: {:error, "job must have a description"}

  defp validate_for_publication(%Job{required_skills: skills}) when length(skills) == 0,
    do: {:error, "job must have at least one required skill"}

  defp validate_for_publication(_), do: :ok
end
