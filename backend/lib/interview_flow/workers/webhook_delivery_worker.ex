defmodule InterviewFlow.Workers.WebhookDeliveryWorker do
  @moduledoc """
  Oban worker for asynchronous webhook delivery with retry.

  Race condition fix (May 2026):
  When two concurrent webhook delivery attempts ran for the same endpoint
  (e.g., a retry job started while the original was still in flight due to
  a slow external server), both would:
  1. Read the same failure_count from the database
  2. Both increment by 1, resulting in failure_count = original + 1 instead of +2
  3. On success, both reset failure_count to 0 — silently dropping the failure count

  More critically, if one attempt succeeded and one failed simultaneously, the
  failed attempt could overwrite the successful attempt's last_triggered_at reset.

  Fix: use Postgres advisory locks keyed on the endpoint_id to serialize concurrent
  delivery attempts for the same endpoint. The lock is held only for the DB update,
  not for the HTTP call itself (which would hold the lock too long and block retries).
  """

  use Oban.Worker,
    queue: :webhooks,
    max_attempts: 5,
    unique: [period: 60, fields: [:args], keys: [:endpoint_id, :event_type]]

  require Logger

  alias InterviewFlow.Webhooks.Delivery
  alias InterviewFlow.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"endpoint_id" => endpoint_id, "event_type" => event_type, "payload" => payload}}) do
    Logger.info("[WebhookDelivery] delivering #{event_type} to endpoint #{endpoint_id}")

    case Delivery.deliver(endpoint_id, event_type, payload) do
      {:ok, status_code} ->
        Logger.info("[WebhookDelivery] delivered successfully (HTTP #{status_code})")
        :ok

      {:ok, :skipped} ->
        Logger.info("[WebhookDelivery] endpoint #{endpoint_id} is disabled, skipping")
        :ok

      {:error, reason} ->
        Logger.warning("[WebhookDelivery] delivery failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Acquires a Postgres advisory lock for the given endpoint to serialize
  concurrent delivery state updates. Lock is released at transaction end.
  """
  def with_endpoint_lock(endpoint_id, fun) do
    # Use a hash of the endpoint UUID to fit within bigint lock key range
    lock_key = :erlang.phash2(endpoint_id, 2_147_483_647)

    Repo.transaction(fn ->
      Repo.query!("SELECT pg_advisory_xact_lock($1)", [lock_key])
      fun.()
    end)
  end
end
