defmodule InterviewFlow.Repo.Migrations.AddAuditLogIndexesAndSecurityColumns do
  use Ecto.Migration

  @doc """
  Schema changes for the security hardening phase (March 2026).

  1. Audit log table indexes for admin UI pagination and SIEM queries.
  2. Add `last_login_at`, `login_count`, `failed_login_count`, and
     `locked_until` columns to users for brute-force detection.
  3. Add `ip_address` and `user_agent` to audit_logs for forensic analysis.
  4. Add partial index on applications for exported_at (export audit trail).
  """

  def change do
    # ── Audit log ────────────────────────────────────────────────────────

    # The admin audit trail UI paginates by company + time descending
    create index(:audit_logs, [:company_id, :inserted_at],
      name: :audit_logs_company_time_idx
    )

    # SIEM queries filter by action type for alerting rules
    create index(:audit_logs, [:action, :inserted_at],
      name: :audit_logs_action_time_idx
    )

    # Resource history lookup (application timeline view)
    create index(:audit_logs, [:resource_type, :resource_id, :inserted_at],
      name: :audit_logs_resource_history_idx
    )

    # Partitioning prep: index on actor for suspicious user sweep queries
    create index(:audit_logs, [:actor_id, :inserted_at],
      name: :audit_logs_actor_time_idx
    )

    # Add forensic columns to audit_logs
    alter table(:audit_logs) do
      add :ip_address,  :string, size: 45  # supports IPv6
      add :user_agent,  :string, size: 512
      add :request_id,  :string, size: 64   # correlation ID
    end

    # ── Users: brute-force and lockout tracking ───────────────────────────

    alter table(:users) do
      add :last_login_at,       :utc_datetime_usec
      add :login_count,         :integer, default: 0, null: false
      add :failed_login_count,  :integer, default: 0, null: false
      add :locked_until,        :utc_datetime_usec
      add :last_seen_ip,        :string, size: 45
      add :mfa_enabled,         :boolean, default: false, null: false
      add :mfa_secret,          :binary   # encrypted via Cloak
    end

    # Index for account lockout check on login path
    create index(:users, [:email, :locked_until],
      name: :users_email_lockout_idx,
      where: "locked_until IS NOT NULL"
    )

    # ── Applications: export audit ────────────────────────────────────────

    alter table(:applications) do
      add :exported_at, :utc_datetime_usec
      add :exported_by, :uuid, references(:users, on_delete: :nilify_all)
    end

    create index(:applications, [:exported_at],
      name: :applications_exported_at_idx,
      where: "exported_at IS NOT NULL"
    )
  end
end
