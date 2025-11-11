defmodule InterviewFlow.Repo.Migrations.CreateCandidates do
  use Ecto.Migration

  def change do
    create table(:candidates, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :company_id, references(:companies, type: :binary_id, on_delete: :restrict), null: false
      add :email, :string, null: false
      add :email_encrypted, :binary, null: false
      add :full_name, :string, null: false
      add :phone, :string
      add :phone_encrypted, :binary
      add :linkedin_url, :text
      add :github_url, :text
      add :portfolio_url, :text
      add :resume_url, :text
      add :resume_text, :text
      add :tags, {:array, :string}, null: false, default: []
      add :source, :string
      add :notes, :text
      add :deleted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    execute """
      ALTER TABLE candidates ADD COLUMN search_vector tsvector
        GENERATED ALWAYS AS (
          to_tsvector('english',
            coalesce(full_name, '') || ' ' ||
            coalesce(resume_text, '') || ' ' ||
            coalesce(notes, ''))
        ) STORED
    """, "ALTER TABLE candidates DROP COLUMN search_vector"

    create unique_index(:candidates, [:company_id, :email])
    create index(:candidates, [:company_id])
    execute "CREATE INDEX idx_candidates_search ON candidates USING GIN (search_vector)", "DROP INDEX IF EXISTS idx_candidates_search"
    execute "CREATE INDEX idx_candidates_tags ON candidates USING GIN (tags)", "DROP INDEX IF EXISTS idx_candidates_tags"
  end
end
