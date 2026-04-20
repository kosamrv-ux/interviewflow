defmodule InterviewFlow.Repo.Migrations.AddOrgIdToResources do
  use Ecto.Migration

  def change do
    # Create organizations table
    create table(:organizations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :slug, :string, null: false
      add :plan, :string, null: false, default: "starter"
      add :settings, :map, default: %{}
      add :sso_enabled, :boolean, default: false
      add :sso_provider, :string
      add :sso_config, :map, default: %{}
      add :max_seats, :integer, default: 5
      add :inserted_at, :utc_datetime_usec
      add :updated_at, :utc_datetime_usec
    end

    create unique_index(:organizations, [:slug])

    # Add org_id to users
    alter table(:users) do
      add :org_id, references(:organizations, type: :binary_id, on_delete: :restrict)
      add :org_role, :string, default: "member"
    end

    create index(:users, [:org_id])

    # Add org_id to jobs
    alter table(:jobs) do
      add :org_id, references(:organizations, type: :binary_id, on_delete: :cascade), null: false
    end

    create index(:jobs, [:org_id])

    # Add org_id to candidates
    alter table(:candidates) do
      add :org_id, references(:organizations, type: :binary_id, on_delete: :cascade), null: false
    end

    create index(:candidates, [:org_id])

    # Add org_id to interviews
    alter table(:interviews) do
      add :org_id, references(:organizations, type: :binary_id, on_delete: :cascade), null: false
    end

    create index(:interviews, [:org_id])

    # Add org_id to applications
    alter table(:applications) do
      add :org_id, references(:organizations, type: :binary_id, on_delete: :cascade), null: false
    end

    create index(:applications, [:org_id])

    # Add org_id to audit_logs
    alter table(:audit_logs) do
      add :org_id, references(:organizations, type: :binary_id, on_delete: :cascade)
    end

    create index(:audit_logs, [:org_id, :inserted_at])

    # Seed a default organization for existing data
    execute """
    INSERT INTO organizations (id, name, slug, plan, inserted_at, updated_at)
    VALUES (
      gen_random_uuid(),
      'Default Organization',
      'default',
      'enterprise',
      NOW(),
      NOW()
    )
    """, ""
  end
end
