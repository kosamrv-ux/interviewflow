defmodule InterviewFlow.AuditLog do
  @moduledoc """
  Structured audit logging for security-sensitive operations.

  All writes go to the `audit_logs` PostgreSQL table (append-only; no
  application-level UPDATE/DELETE) and are also emitted as structured JSON
  log lines that stream to Cloud Logging for SIEM integration.

  ## Logged event categories

  | Category    | Events                                                   |
  |-------------|----------------------------------------------------------|
  | auth        | login, logout, register, token_refresh, failed_login     |
  | user        | role_change, deactivate, invite                          |
  | application | advance, reject, hire, update                            |
  | score       | override, rescore                                        |
  | data        | export, bulk_tag, candidate_merge                        |
  | admin       | company_update, settings_change                          |
  | security    | permission_denied, rate_limit_exceeded, suspicious_ip    |

  ## Retention

  Records older than 90 days are archived to GCS cold storage by
  `ArchiveAuditLogWorker` and then deleted from the hot table.

  ## PII handling

  `sanitize_metadata/1` strips known sensitive keys (password, token, secret,
  api_key, etc.) before storage.  Structured log lines do NOT include metadata
  at WARNING level or above to avoid PII leaking into log aggregators.
  """

  require Logger
  import Ecto.Query
  alias InterviewFlow.Repo

  # Fields stripped from metadata before persisting
  @strip_keys ~w(password password_confirmation token secret api_key credit_card ssn)

  @doc """
  Logs a state transition or sensitive action.

  ## Parameters
  - `company_id`    — tenant scope (nil for system-level events)
  - `actor_id`      — UUID of the user performing the action (nil for workers)
  - `resource_type` — entity type, e.g. "application", "ai_score"
  - `resource_id`   — UUID of the affected record
  - `action`        — event name, e.g. "stage_changed", "score_overridden"
  - `state_change`  — map with `:from` / `:to` keys or arbitrary context
  - `metadata`      — optional additional context (PII-sanitized before write)

  Failures are caught and logged — audit failures never break the request path.
  """
  def log(company_id, actor_id, resource_type, resource_id, action, state_change, metadata \\ %{}) do
    clean_meta = sanitize_metadata(Map.merge(metadata, state_change))

    entry = %{
      id:             Ecto.UUID.generate(),
      company_id:     company_id,
      actor_id:       actor_id,
      resource_type:  to_string(resource_type),
      resource_id:    resource_id,
      action:         to_string(action),
      previous_state: state_change[:from] && %{value: state_change[:from]},
      next_state:     state_change[:to]   && %{value: state_change[:to]},
      metadata:       clean_meta,
      inserted_at:    DateTime.utc_now() |> DateTime.truncate(:microsecond)
    }

    # Fire-and-forget async DB write (never blocks request path)
    Task.Supervisor.start_child(
      InterviewFlow.TaskSupervisor,
      fn ->
        Repo.insert_all("audit_logs", [entry])
      rescue
        e -> Logger.error("audit_log: persist failed", error: inspect(e))
      end
    )

    # Synchronous structured log (always emitted for Cloud Logging / SIEM)
    Logger.info("audit_event",
      company_id:   company_id,
      actor_id:     actor_id,
      resource:     resource_type,
      resource_id:  resource_id,
      action:       action
    )

    :ok
  end

  @doc """
  Logs a security event at WARNING level (immediate SIEM visibility).
  Does NOT include metadata in log line to avoid accidental PII exposure.
  """
  def log_security(actor_id, event, metadata \\ %{}) do
    Logger.warning("security_event", actor_id: actor_id, event: event)
    log(nil, actor_id, "security", nil, event, metadata)
  end

  @doc "Returns audit log entries for a specific resource."
  def for_resource(resource_type, resource_id, limit \\ 50) do
    "audit_logs"
    |> where([a], a.resource_type == ^resource_type and a.resource_id == ^resource_id)
    |> order_by([a], desc: a.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "Paginates audit log entries for a company (admin view)."
  def list_for_company(company_id, opts \\ []) do
    limit    = min(Keyword.get(opts, :limit, 50), 200)
    before   = Keyword.get(opts, :before)
    resource = Keyword.get(opts, :resource)
    actor_id = Keyword.get(opts, :actor_id)

    "audit_logs"
    |> where([a], a.company_id == ^company_id)
    |> maybe_filter_resource(resource)
    |> maybe_filter_actor(actor_id)
    |> maybe_before_cursor(before)
    |> order_by([a], desc: a.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  # ── Private ───────────────────────────────────────────────────────────────

  defp sanitize_metadata(metadata) when is_map(metadata) do
    Enum.reject(metadata, fn {k, _v} -> to_string(k) in @strip_keys end)
    |> Map.new()
  end

  defp sanitize_metadata(other), do: %{raw: inspect(other)}

  defp maybe_filter_resource(q, nil),       do: q
  defp maybe_filter_resource(q, resource),  do: where(q, [a], a.resource_type == ^resource)

  defp maybe_filter_actor(q, nil),      do: q
  defp maybe_filter_actor(q, actor_id), do: where(q, [a], a.actor_id == ^actor_id)

  defp maybe_before_cursor(q, nil),    do: q
  defp maybe_before_cursor(q, before), do: where(q, [a], a.inserted_at < ^before)
end
