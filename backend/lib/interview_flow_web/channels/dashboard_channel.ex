defmodule InterviewFlowWeb.DashboardChannel do
  @moduledoc """
  Real-time dashboard updates channel.
  Pushes pipeline events to recruiter dashboards:
  - Application stage changes
  - New AI scorecards available
  - Interview status updates
  """

  use InterviewFlowWeb, :channel

  @impl true
  def join("dashboard:" <> company_id, _params, socket) do
    # Only allow users from the same company
    if socket.assigns.current_user.company_id == company_id do
      {:ok, %{status: "connected"}, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_info({:pipeline_update, event}, socket) do
    push(socket, "pipeline:update", event)
    {:noreply, socket}
  end

  def handle_info({:scorecard_ready, data}, socket) do
    push(socket, "scorecard:ready", data)
    {:noreply, socket}
  end

  @doc """
  Broadcasts a pipeline update to all connected recruiters for a company.
  Called from Phoenix context modules after state transitions.
  """
  def broadcast_pipeline_update(company_id, event_data) do
    InterviewFlowWeb.Endpoint.broadcast(
      "dashboard:#{company_id}",
      "pipeline:update",
      event_data
    )
  end

  @doc "Broadcasts scorecard availability after AI scoring completes."
  def broadcast_scorecard_ready(company_id, application_id, score_summary) do
    InterviewFlowWeb.Endpoint.broadcast(
      "dashboard:#{company_id}",
      "scorecard:ready",
      %{
        application_id: application_id,
        composite_score: score_summary.composite_score,
        recommended_action: score_summary.recommended_action
      }
    )
  end
end
