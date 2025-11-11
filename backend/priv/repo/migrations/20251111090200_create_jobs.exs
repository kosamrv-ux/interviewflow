defmodule InterviewFlow.Repo.Migrations.CreateJobs do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm", "SELECT 1"

    create table(:jobs, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :company_id, references(:companies, type: :binary_id, on_delete: :restrict), null: false
      add :created_by_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :title, :string, null: false
      add :department, :string
      add :location, :string
      add :remote_policy, :string, null: false, default: "hybrid"
      add :employment_type, :string, null: false, default: "full_time"
      add :description, :text
      add :requirements, :text
      add :salary_min, :integer
      add :salary_max, :integer
      add :salary_currency, :string, null: false, default: "USD", size: 3
      add :pipeline_stages, {:array, :string}, null: false, default: ["applied", "screen", "interview", "offer", "hired"]
      add :scoring_rubric, :map, null: false, default: %{}
      add :status, :string, null: false, default: "draft"
      add :published_at, :utc_datetime_usec
      add :closed_at, :utc_datetime_usec
      add :deleted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    # Full-text search using tsvector (stored in a separate column via trigger)
    execute """
      ALTER TABLE jobs ADD COLUMN search_vector tsvector
        GENERATED ALWAYS AS (
          to_tsvector('english',
            coalesce(title, '') || ' ' ||
            coalesce(department, '') || ' ' ||
            coalesce(location, ''))
        ) STORED
    """, "ALTER TABLE jobs DROP COLUMN search_vector"

    create index(:jobs, [:company_id])
    create index(:jobs, [:status])
    create index(:jobs, [:deleted_at], where: "deleted_at IS NULL", name: :idx_jobs_active)
    execute "CREATE INDEX idx_jobs_search ON jobs USING GIN (search_vector)", "DROP INDEX IF EXISTS idx_jobs_search"
  end
end
