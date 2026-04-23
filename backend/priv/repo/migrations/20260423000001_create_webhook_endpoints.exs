defmodule InterviewFlow.Repo.Migrations.CreateWebhookEndpoints do
  use Ecto.Migration

  def change do
    create table(:webhook_endpoints, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :org_id, references(:organizations, type: :binary_id, on_delete: :cascade), null: false
      add :url, :string, null: false
      add :secret, :string, null: false
      add :events, {:array, :string}, default: []
      add :enabled, :boolean, default: true
      add :description, :string
      add :last_triggered_at, :utc_datetime_usec
      add :failure_count, :integer, default: 0
      add :inserted_at, :utc_datetime_usec
      add :updated_at, :utc_datetime_usec
    end

    create index(:webhook_endpoints, [:org_id])
    create unique_index(:webhook_endpoints, [:org_id, :url])

    create table(:webhook_delivery_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :endpoint_id, references(:webhook_endpoints, type: :binary_id, on_delete: :cascade)
      add :event_type, :string, null: false
      add :status_code, :integer
      add :response_body, :text
      add :duration_ms, :integer
      add :success, :boolean
      add :error_message, :string
      add :inserted_at, :utc_datetime_usec
    end

    create index(:webhook_delivery_logs, [:endpoint_id, :inserted_at])
  end
end
