defmodule InterviewFlow.Repo.Migrations.CreateApiKeys do
  use Ecto.Migration

  def change do
    create table(:api_keys, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :org_id, references(:organizations, type: :binary_id, on_delete: :cascade), null: false
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :name, :string, null: false
      add :key_prefix, :string, null: false
      add :key_hash, :string, null: false
      add :scopes, {:array, :string}, default: ["read"]
      add :last_used_at, :utc_datetime_usec
      add :expires_at, :utc_datetime_usec
      add :revoked_at, :utc_datetime_usec
      add :revoked_by, :binary_id
      add :inserted_at, :utc_datetime_usec
      add :updated_at, :utc_datetime_usec
    end

    create index(:api_keys, [:org_id])
    create unique_index(:api_keys, [:key_prefix])
  end
end
