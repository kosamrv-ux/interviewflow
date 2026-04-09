defmodule InterviewFlow.Repo.Migrations.AddCandidateSearchVectorAndConstraints do
  use Ecto.Migration

  @moduledoc """
  Adds a tsvector search column and trigger for candidates full-text search,
  and adds a constraint preventing duplicate active applications per candidate
  per job.

  ## Why

  The current full-text search in maybe_search_candidates/2 uses
  `plainto_tsquery` over raw columns which cannot be index-accelerated
  without a generated tsvector column.

  The duplicate application constraint closes a race condition where a
  candidate can submit two applications for the same job before the first
  is persisted.
  """

  def up do
    # ── Add search_vector tsvector column ────────────────────────────────

    # shadow plaintext columns for search (the actual email/name are encrypted)
    alter table(:candidates) do
      add :search_name,   :string, size: 512
      add :search_email,  :string, size: 255
      add :search_vector, :tsvector
    end

    # Trigger to keep search_vector up to date
    execute """
    CREATE OR REPLACE FUNCTION candidates_search_vector_update()
    RETURNS trigger AS $$
    BEGIN
      NEW.search_vector :=
        setweight(to_tsvector('english', coalesce(NEW.search_name, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(NEW.search_email, '')), 'B');
      RETURN NEW;
    END
    $$ LANGUAGE plpgsql;
    """

    execute """
    CREATE TRIGGER candidates_search_vector_trigger
      BEFORE INSERT OR UPDATE ON candidates
      FOR EACH ROW EXECUTE FUNCTION candidates_search_vector_update();
    """

    # GIN index on tsvector for fast full-text search
    execute """
    CREATE INDEX candidates_search_vector_gin_idx
      ON candidates USING gin(search_vector)
    """

    # ── Unique constraint: one active application per candidate per job ───

    # Uses a partial unique index to allow multiple rejected/withdrawn
    # applications (for re-application scenarios) while preventing duplicates
    # in the active pipeline.
    execute """
    CREATE UNIQUE INDEX applications_unique_active_per_candidate_job_idx
      ON applications (job_id, candidate_id)
      WHERE status NOT IN ('rejected', 'withdrawn')
    """
  end

  def down do
    execute "DROP INDEX IF EXISTS applications_unique_active_per_candidate_job_idx"
    execute "DROP INDEX IF EXISTS candidates_search_vector_gin_idx"
    execute "DROP TRIGGER IF EXISTS candidates_search_vector_trigger ON candidates"
    execute "DROP FUNCTION IF EXISTS candidates_search_vector_update()"

    alter table(:candidates) do
      remove :search_vector
      remove :search_email
      remove :search_name
    end
  end
end
