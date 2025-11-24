defmodule InterviewFlow.AuditLog do
  @moduledoc """
  Writes immutable audit log entries for significant state transitions.
  Called from context modules to record who did what and when.
  """

  import Ecto.Query
  alias InterviewFlow.Repo

  @doc """
  Logs a state transition event.

  ## Parameters
  - `company_id` — company scope for the event
  - `actor_id` — UUID of the user who triggered the action (nil for system actions)
  - `resource_type` — entity type, e.g. "application", "ai_score"
  - `resource_id` — UUID of the affected record
  - `action` — event name, e.g. "stage_changed", "score_overridden"
  - `state_change` — map with `:from` and `:to` keys or arbitrary context
  - `metadata` — optional additional context map
  """
  def log(company_id, actor_id, resource_type, resource_id, action, state_change, metadata \\ %{}) do
    entry = %{
      id: Ecto.UUID.generate(),
      company_id: company_id,
      actor_id: actor_id,
      resource_type: to_string(resource_type),
      resource_id: resource_id,
      action: to_string(action),
      previous_state: state_change[:from] && %{value: state_change[:from]},
      next_state: state_change[:to] && %{value: state_change[:to]},
      metadata: Map.merge(metadata, state_change),
      inserted_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
    }

    Repo.insert_all("audit_logs", [entry])
    :ok
  end

  @doc "Returns audit log entries for a specific resource."
  def for_resource(resource_type, resource_id, limit \\ 50) do
    "audit_logs"
    |> where([a], a.resource_type == ^resource_type and a.resource_id == ^resource_id)
    |> order_by([a], [desc: a.inserted_at])
    |> limit(^limit)
    |> Repo.all()
  end
end
