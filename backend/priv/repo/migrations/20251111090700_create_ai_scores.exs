defmodule InterviewFlow.Repo.Migrations.CreateAiScores do
  use Ecto.Migration

  def change do
    create table(:ai_scores, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :application_id, references(:applications, type: :binary_id, on_delete: :restrict), null: false
      add :video_session_id, references(:video_sessions, type: :binary_id, on_delete: :nilify_all)
      add :scored_by, :string, null: false, default: "vertex_ai_gemini_1_5_pro"
      add :model_version, :string
      add :composite_score, :decimal, precision: 4, scale: 2, null: false
      add :breakdown, :map, null: false
      add :strengths, {:array, :string}
      add :areas_for_growth, {:array, :string}
      add :recommended_action, :string
      add :confidence, :decimal, precision: 4, scale: 3
      add :prompt_version, :string
      add :raw_response, :text
      add :processing_ms, :integer
      add :status, :string, null: false, default: "completed"
      add :overridden_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create table(:audit_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :company_id, references(:companies, type: :binary_id, on_delete: :restrict), null: false
      add :actor_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :resource_type, :string, null: false
      add :resource_id, :binary_id, null: false
      add :action, :string, null: false
      add :previous_state, :map
      add :next_state, :map
      add :metadata, :map, null: false, default: %{}
      add :ip_address, :string
      add :user_agent, :text
      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create unique_index(:ai_scores, [:application_id, :video_session_id])
    create index(:ai_scores, [:application_id])
    create index(:ai_scores, [:composite_score])
    create index(:audit_logs, [:company_id])
    create index(:audit_logs, [:resource_type, :resource_id])
    create index(:audit_logs, [:actor_id])
    create index(:audit_logs, [:inserted_at])
  end
end
