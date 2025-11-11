defmodule InterviewFlow.Repo.Migrations.CreateCompanies do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS pgcrypto", "SELECT 1"

    create table(:companies, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :name, :string, null: false
      add :slug, :string, null: false
      add :domain, :string
      add :plan, :string, null: false, default: "trial"
      add :seats_limit, :integer, null: false, default: 5
      add :logo_url, :text
      add :settings, :map, null: false, default: %{}
      add :deleted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:companies, [:slug])
    create index(:companies, [:deleted_at], where: "deleted_at IS NULL", name: :idx_companies_active)
  end
end
