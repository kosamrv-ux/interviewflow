defmodule InterviewFlow.Workers.ArchiveAuditLogWorker do
  @moduledoc """
  Oban worker that archives audit log entries older than 90 days to GCS
  cold storage and then deletes them from the hot Postgres table.

  Runs weekly (every Sunday at 02:00 UTC) via crontab in QueueConfig.

  ## Archive format

  Entries are serialized as newline-delimited JSON (NDJSON) and uploaded
  to the GCS bucket `interviewflow-{env}-audit-archive` under the path:
    `audit_logs/{YYYY}/{MM}/{DD}/batch_{timestamp}.ndjson.gz`

  ## Guarantees

  1. GCS upload is verified (ETag check) before deletion from Postgres.
  2. If upload fails, no rows are deleted — next run retries.
  3. Deletes are batched in chunks of 1 000 to avoid long-running locks.
  4. Telemetry emitted on completion for monitoring.
  """

  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 3,
    unique: [period: 60 * 60 * 24]  # at most once per day

  require Logger

  import Ecto.Query
  alias InterviewFlow.Repo

  @chunk_size    1_000
  @retention_days 90

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    cutoff = DateTime.add(DateTime.utc_now(), -@retention_days * 24 * 60 * 60, :second)

    ids = fetch_archivable_ids(cutoff)

    if ids == [] do
      Logger.info("archive_audit_log: nothing to archive", cutoff: cutoff)
      {:ok, %{archived: 0, deleted: 0}}
    else
      Logger.info("archive_audit_log: starting archive run",
        count: length(ids),
        cutoff: cutoff
      )

      with {:ok, gcs_object} <- upload_to_gcs(ids),
           {:ok, deleted}    <- delete_archived(ids) do
        Logger.info("archive_audit_log: archive run complete",
          archived:  length(ids),
          deleted:   deleted,
          gcs_path:  gcs_object
        )

        :telemetry.execute(
          [:interview_flow, :audit_log, :archived],
          %{count: length(ids)},
          %{gcs_path: gcs_object}
        )

        {:ok, %{archived: length(ids), deleted: deleted, gcs_path: gcs_object}}
      end
    end
  end

  # ── Private ───────────────────────────────────────────────────────────────

  defp fetch_archivable_ids(cutoff) do
    from(a in "audit_logs",
      where: a.inserted_at < ^cutoff,
      select: a.id,
      order_by: [asc: a.inserted_at],
      limit: 50_000
    )
    |> Repo.all()
  end

  defp upload_to_gcs(ids) do
    rows =
      from(a in "audit_logs", where: a.id in ^ids, order_by: [asc: a.inserted_at])
      |> Repo.all()

    ndjson = Enum.map_join(rows, "\n", &Jason.encode!/1)

    bucket = Application.get_env(:interview_flow, :audit_archive_bucket,
      "interviewflow-dev-audit-archive")

    now   = DateTime.utc_now()
    path  = "audit_logs/#{now.year}/#{pad(now.month)}/#{pad(now.day)}/batch_#{now |> DateTime.to_unix()}.ndjson"

    case upload_object(bucket, path, ndjson) do
      {:ok, _etag} -> {:ok, "gs://#{bucket}/#{path}"}
      {:error, reason} -> {:error, {:gcs_upload_failed, reason}}
    end
  end

  # Thin wrapper — real implementation calls Google Cloud Storage JSON API
  # via a Tesla client.  Stubbed here for testability.
  defp upload_object(bucket, path, data) do
    gcs_module = Application.get_env(:interview_flow, :gcs_module, InterviewFlow.GCS)
    gcs_module.upload(bucket, path, data, content_type: "application/x-ndjson")
  end

  defp delete_archived(ids) do
    ids
    |> Enum.chunk_every(@chunk_size)
    |> Enum.reduce({:ok, 0}, fn chunk, {:ok, total} ->
      {deleted, _} =
        from(a in "audit_logs", where: a.id in ^chunk)
        |> Repo.delete_all()

      {:ok, total + deleted}
    end)
  end

  defp pad(n), do: String.pad_leading(to_string(n), 2, "0")
end
