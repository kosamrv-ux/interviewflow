defmodule InterviewFlow.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :company_id, references(:companies, type: :binary_id, on_delete: :restrict), null: false
      add :email, :string, null: false
      add :email_encrypted, :binary
      add :hashed_password, :string, null: false
      add :full_name, :string, null: false
      add :avatar_url, :text
      add :role, :string, null: false, default: "recruiter"
      add :confirmed_at, :utc_datetime_usec
      add :last_sign_in_at, :utc_datetime_usec
      add :deactivated_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:users, [:email])
    create index(:users, [:company_id])
    create index(:users, [:deactivated_at], where: "deactivated_at IS NULL", name: :idx_users_active)
  end
end
