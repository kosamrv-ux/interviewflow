defmodule InterviewFlow.Workers.PurgeExpiredSessionsWorker do
  @moduledoc """
  Oban worker that runs nightly to end video sessions that were never properly
  closed — for example when a browser tab crashed without sending the end signal.

  Marks sessions as :ended after a configurable idle timeout window and computes
  a best-effort duration from the activated_at timestamp.  Sessions that never
  activated (joined but no media negotiation) are marked as :abandoned instead.

  Runs via the cron schedule configured in config/config.exs:
    {"0 3 * * *", InterviewFlow.Workers.PurgeExpiredSessionsWorker}
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3

  import Ecto.Query

  alias InterviewFlow.Repo
  alias InterviewFlow.Interviews.VideoSession

  # Sessions idle for more than 4 hours are considered stale.
  @stale_threshold_hours 4

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    cutoff = DateTime.add(DateTime.utc_now(), -@stale_threshold_hours * 3600, :second)

    stale_active_ids = stale_active_session_ids(cutoff)
    never_activated_ids = never_activated_session_ids(cutoff)

    {ended_count, _} = end_stale_sessions(stale_active_ids, cutoff)
    {abandoned_count, _} = abandon_never_activated(never_activated_ids)

    :telemetry.execute(
      [:interview_flow, :purge_sessions, :completed],
      %{ended: ended_count, abandoned: abandoned_count},
      %{}
    )

    :ok
  end

  # Sessions that were activated (activated_at IS NOT NULL) but never ended.
  defp stale_active_session_ids(cutoff) do
    from(vs in VideoSession,
      where: vs.status == :active,
      where: not is_nil(vs.activated_at),
      where: vs.activated_at < ^cutoff,
      select: vs.id
    )
    |> Repo.all()
  end

  # Sessions that were created but never had media exchange.
  defp never_activated_session_ids(cutoff) do
    from(vs in VideoSession,
      where: vs.status == :pending,
      where: is_nil(vs.activated_at),
      where: vs.inserted_at < ^cutoff,
      select: vs.id
    )
    |> Repo.all()
  end

  defp end_stale_sessions([], _cutoff), do: {0, nil}

  defp end_stale_sessions(ids, cutoff) do
    now = DateTime.utc_now()

    # Compute duration per session using activated_at and cutoff as the end time.
    from(vs in VideoSession,
      where: vs.id in ^ids,
      update: [
        set: [
          status: :ended,
          ended_at: ^now,
          duration_seconds: fragment("EXTRACT(EPOCH FROM (? - activated_at))::int", ^cutoff),
          updated_at: ^now
        ]
      ]
    )
    |> Repo.update_all([])
  end

  defp abandon_never_activated([]), do: {0, nil}

  defp abandon_never_activated(ids) do
    now = DateTime.utc_now()

    from(vs in VideoSession,
      where: vs.id in ^ids,
      update: [set: [status: :abandoned, ended_at: ^now, updated_at: ^now]]
    )
    |> Repo.update_all([])
  end
end
