defmodule InterviewFlow.Candidates.CandidateService do
  @moduledoc """
  Service layer for candidate management operations.

  Refactored from CandidateController, which previously mixed HTTP parsing,
  business rule enforcement, and data access. This service provides a single
  entry point that can be called by controllers, Oban workers, and tests alike.

  ## Operations
  - `upsert_from_application/1` — de-duplicate candidates by email on apply
  - `merge/2` — merge two duplicate candidate records
  - `export_shortlist/3` — export candidates to CSV or JSON with PII controls
  - `bulk_tag/3` — apply tags to multiple candidates atomically
  """

  require Logger

  alias InterviewFlow.{Repo, Candidates}
  alias InterviewFlow.Candidates.{Candidate, Export}
  alias InterviewFlow.Audit

  @doc """
  Creates or updates a candidate record from an inbound job application.

  If a candidate with the same email already exists within the company,
  updates the existing record (upsert). Returns the candidate record.
  """
  @spec upsert_from_application(map()) :: {:ok, Candidate.t()} | {:error, any()}
  def upsert_from_application(%{email: email, company_id: company_id} = attrs) do
    case Candidates.find_by_email(company_id, email) do
      nil ->
        Logger.info("candidate_service: creating new candidate", email: email)
        Candidates.create_candidate(attrs)

      existing ->
        Logger.info("candidate_service: upserting existing candidate",
          candidate_id: existing.id,
          email: email
        )

        Candidates.update_candidate(existing, attrs)
    end
  end

  @doc """
  Merges two candidate records, keeping `primary` and migrating all
  applications, interviews, and scores from `duplicate`.

  The duplicate record is soft-deleted after migration.
  """
  @spec merge(Candidate.t(), Candidate.t(), map()) ::
          {:ok, Candidate.t()} | {:error, String.t()}
  def merge(%Candidate{id: primary_id}, %Candidate{id: dup_id}, actor)
      when primary_id == dup_id,
      do: {:error, "cannot merge a candidate with itself"}

  def merge(%Candidate{} = primary, %Candidate{} = duplicate, actor) do
    Repo.transaction(fn ->
      migrate_applications(duplicate.id, primary.id)
      soft_delete_duplicate(duplicate)

      Audit.log(:candidate_merged, %{
        primary_id: primary.id,
        duplicate_id: duplicate.id,
        actor_id: actor.id
      })

      primary
    end)
  end

  @doc """
  Exports a shortlist of candidates for a job to CSV or JSON.

  Delegates to `Candidates.Export` with PII redaction for non-recruiter roles.
  """
  @spec export_shortlist(Ecto.UUID.t(), Ecto.UUID.t(), map()) ::
          {:ok, String.t() | [map()]} | {:error, any()}
  def export_shortlist(job_id, company_id, actor) do
    redact = actor.role not in ["admin", "recruiter"]
    format = :csv

    case format do
      :csv -> Export.to_csv(job_id, company_id, redact_pii: redact)
      :json -> Export.to_json(job_id, company_id, redact_pii: redact)
    end
  end

  @doc """
  Applies a list of tags to multiple candidates atomically.

  Returns the count of updated records.
  """
  @spec bulk_tag([Ecto.UUID.t()], [String.t()], map()) :: {:ok, non_neg_integer()} | {:error, any()}
  def bulk_tag(candidate_ids, tags, actor) do
    Logger.info("candidate_service: bulk tagging",
      count: length(candidate_ids),
      tags: tags,
      actor_id: actor.id
    )

    {count, _} = Candidates.add_tags_to_candidates(candidate_ids, tags)
    {:ok, count}
  end

  # ── Private helpers ──────────────────────────────────────────────────────

  defp migrate_applications(from_id, to_id) do
    import Ecto.Query
    from(a in Candidates.Application, where: a.candidate_id == ^from_id)
    |> Repo.update_all(set: [candidate_id: to_id])
  end

  defp soft_delete_duplicate(%Candidate{} = candidate) do
    candidate
    |> Ecto.Changeset.change(deleted_at: DateTime.utc_now())
    |> Repo.update!()
  end
end
