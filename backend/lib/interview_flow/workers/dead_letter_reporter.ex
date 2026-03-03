defmodule InterviewFlow.Workers.DeadLetterReporter do
  @moduledoc """
  Oban worker that polls for discarded jobs and pages on-call when the
  discard rate exceeds configured thresholds.

  Runs every 10 minutes via crontab in QueueConfig.

  ## Alert thresholds

  | Queue    | Discard count (10 min window) | Action                  |
  |----------|-------------------------------|-------------------------|
  | scoring  | >= 5                          | PagerDuty P2 alert      |
  | mailer   | >= 10                         | PagerDuty P3 alert      |
  | any      | >= 25                         | PagerDuty P1 alert      |

  Discarded jobs are also logged to structured JSON for Grafana alerting.
  """

  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 1,
    unique: [period: 60 * 9]

  require Logger

  import Ecto.Query
  alias InterviewFlow.Repo

  @thresholds %{
    "scoring"  => {5,  :p2},
    "mailer"   => {10, :p3},
    "__total__" => {25, :p1}
  }

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    window_start = DateTime.add(DateTime.utc_now(), -10 * 60, :second)

    discards =
      from(j in Oban.Job,
        where: j.state == "discarded" and j.discarded_at >= ^window_start,
        group_by: j.queue,
        select: {j.queue, count(j.id)}
      )
      |> Repo.all()
      |> Map.new()

    total = Enum.sum(Map.values(discards))
    discards_with_total = Map.put(discards, "__total__", total)

    Logger.info("dead_letter_reporter: discard sweep",
      discards: discards,
      total: total,
      window_minutes: 10
    )

    Enum.each(discards_with_total, fn {queue, count} ->
      case Map.get(@thresholds, queue) do
        {threshold, priority} when count >= threshold ->
          fire_alert(queue, count, priority)

        _ ->
          :ok
      end
    end)

    {:ok, %{discards: discards, total: total}}
  end

  defp fire_alert(queue, count, priority) do
    Logger.error("dead_letter_reporter: threshold exceeded — firing alert",
      queue: queue,
      count: count,
      priority: priority
    )

    :telemetry.execute(
      [:interview_flow, :oban, :dead_letter_alert],
      %{count: count},
      %{queue: queue, priority: priority}
    )

    # In production this calls the PagerDuty Events API v2.
    # Stubbed here; the actual client is in InterviewFlow.Alerting.PagerDuty.
    if Application.get_env(:interview_flow, :pagerduty_enabled, false) do
      InterviewFlow.Alerting.PagerDuty.trigger(%{
        summary: "Oban dead-letter threshold exceeded: #{count} discards in #{queue}",
        severity: priority_to_severity(priority),
        source: "interviewflow/dead-letter-reporter",
        custom_details: %{queue: queue, count: count, priority: priority}
      })
    end
  end

  defp priority_to_severity(:p1), do: "critical"
  defp priority_to_severity(:p2), do: "error"
  defp priority_to_severity(:p3), do: "warning"
end
