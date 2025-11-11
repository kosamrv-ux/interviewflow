defmodule InterviewFlow.Repo.Migrations.CreateVideoSessions do
  use Ecto.Migration

  def change do
    create table(:video_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :interview_id, references(:interviews, type: :binary_id, on_delete: :restrict), null: false
      add :session_token, :string, null: false
      add :status, :string, null: false, default: "waiting"
      add :started_at, :utc_datetime_usec
      add :ended_at, :utc_datetime_usec
      add :duration_seconds, :integer
      add :recording_url, :text
      add :transcript_url, :text
      add :participant_count, :integer, null: false, default: 0
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:video_sessions, [:session_token])
    create index(:video_sessions, [:interview_id])
    create index(:video_sessions, [:status])
  end
end
