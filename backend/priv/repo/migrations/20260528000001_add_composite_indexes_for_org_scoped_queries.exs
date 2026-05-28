defmodule InterviewFlow.Repo.Migrations.AddCompositeIndexesForOrgScopedQueries do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    # Interviews: most common query pattern is org_id + status + scheduled_at range
    create_if_not_exists index(:interviews, [:org_id, :status, :scheduled_at],
      name: :interviews_org_status_scheduled_idx,
      concurrently: true
    )

    # Interviews: org_id + candidate_id for candidate timeline queries
    create_if_not_exists index(:interviews, [:org_id, :candidate_id, :scheduled_at],
      name: :interviews_org_candidate_scheduled_idx,
      concurrently: true
    )

    # Interviews: org_id + job_id for job pipeline views
    create_if_not_exists index(:interviews, [:org_id, :job_id, :status],
      name: :interviews_org_job_status_idx,
      concurrently: true
    )

    # Candidates: org_id + status for dashboard counts
    create_if_not_exists index(:candidates, [:org_id, :status],
      name: :candidates_org_status_idx,
      concurrently: true
    )

    # Applications: org_id + job_id + stage for funnel queries
    create_if_not_exists index(:applications, [:org_id, :job_id, :stage],
      name: :applications_org_job_stage_idx,
      concurrently: true
    )

    # Applications: org_id + candidate_id for candidate application history
    create_if_not_exists index(:applications, [:org_id, :candidate_id, :inserted_at],
      name: :applications_org_candidate_inserted_idx,
      concurrently: true
    )

    # Audit logs: org_id + inserted_at already exists; add actor_id + action combo
    create_if_not_exists index(:audit_logs, [:org_id, :actor_id, :inserted_at],
      name: :audit_logs_org_actor_inserted_idx,
      concurrently: true
    )

    create_if_not_exists index(:audit_logs, [:org_id, :resource_type, :resource_id],
      name: :audit_logs_org_resource_idx,
      concurrently: true
    )

    # API keys: org_id + revoked_at for listing active keys efficiently
    create_if_not_exists index(:api_keys, [:org_id, :revoked_at],
      name: :api_keys_org_revoked_idx,
      concurrently: true
    )

    # Webhook endpoints: org_id + enabled for dispatch queries
    create_if_not_exists index(:webhook_endpoints, [:org_id, :enabled],
      name: :webhook_endpoints_org_enabled_idx,
      concurrently: true
    )
  end
end
