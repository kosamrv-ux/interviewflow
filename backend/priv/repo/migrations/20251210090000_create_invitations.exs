defmodule InterviewFlow.Repo.Migrations.CreateInvitations do
  use Ecto.Migration

  def change do
    create table(:invitations, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :company_id, references(:companies, type: :binary_id, on_delete: :delete_all), null: false
      add :invited_by_id, references(:users, type: :binary_id, on_delete: :nilify_all), null: false

      add :email, :citext, null: false
      add :full_name, :string, size: 200
      add :role, :string, null: false, default: "recruiter"

      # Secure random token — delivered in the invitation email URL
      add :token, :string, null: false

      add :accepted_at, :utc_datetime_usec
      add :expires_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    # One pending invitation per email per company
    create unique_index(:invitations, [:company_id, :email],
             name: :invitations_company_id_email_index,
             where: "accepted_at IS NULL")

    # Index for token lookup during acceptance flow
    create unique_index(:invitations, [:token], name: :invitations_token_index)

    # Recruiter dashboard — filter pending invitations by company
    create index(:invitations, [:company_id, :expires_at])
  end
end
