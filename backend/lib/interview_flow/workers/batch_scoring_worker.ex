defmodule InterviewFlow.Workers.BatchScoringWorker do
  @moduledoc """
  Oban worker that kicks off AI scoring for all completed but un-scored
  video sessions. Runs on a scheduled cron (every 15 minutes) so that
  scores are available without relying solely on the real-time trigger.

  Each application is enqueued into the `scoring` queue as an independent
  `TriggerScoringWorker` job to enable parallel processing and per-job
  retries without blocking the batch.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: 600]

  require Logger

  alias InterviewFlow.{Repo, Workers.TriggerScoringWorker}
  alias InterviewFlow.Interviews.VideoSession

  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    application_ids = find_unscored_applications()

    Logger.info("batch_scoring_worker: enqueueing scoring jobs",
      count: length(application_ids)
    )

    jobs =
      Enum.map(application_ids, fn app_id ->
        TriggerScoringWorker.new(%{application_id: app_id}, queue: :scoring)
      end)

    Oban.insert_all(jobs)

    {:ok, %{enqueued: length(application_ids)}}
  end

  # ── Helpers ──────────────────────────────────────────────────────────────

  defp find_unscored_applications do
    cutoff = DateTime.add(DateTime.utc_now(), -5 * 60, :second)

    from(vs in VideoSession,
      join: i in assoc(vs, :interview),
      left_join: s in assoc(i, :application),
      where:
        vs.status == "ended" and
          vs.ended_at <= ^cutoff and
          is_nil(s.latest_ai_score_id),
      distinct: i.application_id,
      select: i.application_id
    )
    |> Repo.all()
  end
end
