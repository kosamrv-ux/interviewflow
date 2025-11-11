defmodule InterviewFlow.Repo.Migrations.CreateInterviews do
  use Ecto.Migration

  def change do
    create table(:interviews, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :application_id, references(:applications, type: :binary_id, on_delete: :restrict), null: false
      add :scheduled_by_id, references(:users, type: :binary_id, on_delete: :restrict), null: false
      add :title, :string, null: false
      add :interview_type, :string, null: false, default: "video"
      add :scheduled_at, :utc_datetime_usec, null: false
      add :duration_minutes, :integer, null: false, default: 60
      add :timezone, :string, null: false, default: "UTC"
      add :calendar_event_id, :string
      add :meeting_link, :text
      add :instructions, :text
      add :status, :string, null: false, default: "scheduled"
      add :cancelled_reason, :text
      add :completed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create table(:interview_interviewers, primary_key: false) do
      add :interview_id, references(:interviews, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :role, :string, null: false, default: "interviewer"
      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create primary_key(:interview_interviewers, [:interview_id, :user_id])
    create index(:interviews, [:application_id])
    create index(:interviews, [:scheduled_at])
    create index(:interviews, [:status])
    create index(:interviews, [:scheduled_by_id])
  end
end
