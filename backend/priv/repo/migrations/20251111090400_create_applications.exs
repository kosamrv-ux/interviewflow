defmodule InterviewFlow.Repo.Migrations.CreateApplications do
  use Ecto.Migration

  def change do
    create table(:applications, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :job_id, references(:jobs, type: :binary_id, on_delete: :restrict), null: false
      add :candidate_id, references(:candidates, type: :binary_id, on_delete: :restrict), null: false
      add :assigned_to_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :pipeline_stage, :string, null: false, default: "applied"
      add :rejection_reason, :string
      add :cover_letter, :text
      add :referral_name, :string
      add :source_details, :map, null: false, default: %{}
      add :composite_score, :decimal, precision: 4, scale: 2
      add :rank_within_job, :integer
      add :status, :string, null: false, default: "active"
      add :applied_at, :utc_datetime_usec, null: false, default: fragment("now()")
      add :stage_changed_at, :utc_datetime_usec, null: false, default: fragment("now()")

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:applications, [:job_id, :candidate_id])
    create index(:applications, [:job_id])
    create index(:applications, [:candidate_id])
    create index(:applications, [:pipeline_stage])
    create index(:applications, [:assigned_to_id])
    create index(:applications, [:composite_score])
    create index(:applications, [:status])
  end
end
