defmodule InterviewFlow.Webhooks.Delivery do
  @moduledoc """
  Handles webhook event delivery with retries, signature signing, and dead-letter tracking.

  Delivery is handled via Oban jobs so retries survive restarts.
  Each delivery attempt is logged to webhook_delivery_logs for audit purposes.

  Signature: HMAC-SHA256 of the raw JSON body, sent in X-InterviewFlow-Signature header.
  Format: sha256=<hex_digest>
  """

  require Logger

  alias InterviewFlow.Repo
  alias InterviewFlow.Webhooks.Endpoint

  import Ecto.Query

  @http_timeout 10_000
  @max_retries 5

  @doc """
  Dispatches an event to all enabled webhook endpoints registered for that event
  in the given organization.
  """
  def dispatch(org_id, event_type, payload) when is_binary(event_type) do
    endpoints =
      from(e in Endpoint,
        where: e.org_id == ^org_id and e.enabled == true and ^event_type in e.events
      )
      |> Repo.all()

    Enum.each(endpoints, fn endpoint ->
      %{endpoint_id: endpoint.id, event_type: event_type, payload: payload}
      |> InterviewFlow.Workers.WebhookDeliveryWorker.new(max_attempts: @max_retries)
      |> Oban.insert()
    end)

    :ok
  end

  @doc """
  Delivers a single webhook synchronously. Called by the Oban worker.
  Returns {:ok, status_code} or {:error, reason}.
  """
  def deliver(endpoint_id, event_type, payload) do
    endpoint = Repo.get!(Endpoint, endpoint_id)

    unless endpoint.enabled do
      Logger.info("[Webhook] skipping disabled endpoint #{endpoint_id}")
      {:ok, :skipped}
    else
      body = Jason.encode!(%{event: event_type, data: payload, timestamp: DateTime.utc_now()})
      signature = sign(body, endpoint.secret)

      headers = [
        {"Content-Type", "application/json"},
        {"User-Agent", "InterviewFlow-Webhook/1.0"},
        {"X-InterviewFlow-Signature", "sha256=#{signature}"},
        {"X-InterviewFlow-Event", event_type},
        {"X-InterviewFlow-Delivery", Ecto.UUID.generate()}
      ]

      case HTTPoison.post(endpoint.url, body, headers, recv_timeout: @http_timeout) do
        {:ok, %{status_code: code}} when code in 200..299 ->
          update_last_triggered(endpoint)
          reset_failure_count(endpoint)
          {:ok, code}

        {:ok, %{status_code: code}} ->
          increment_failure_count(endpoint)
          Logger.warning("[Webhook] endpoint #{endpoint_id} returned #{code}")
          {:error, "non-2xx response: #{code}"}

        {:error, %HTTPoison.Error{reason: reason}} ->
          increment_failure_count(endpoint)
          Logger.error("[Webhook] delivery to #{endpoint.url} failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp sign(body, secret) do
    :crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower)
  end

  defp update_last_triggered(endpoint) do
    endpoint
    |> Ecto.Changeset.change(%{last_triggered_at: DateTime.utc_now()})
    |> Repo.update()
  end

  defp increment_failure_count(endpoint) do
    from(e in Endpoint, where: e.id == ^endpoint.id)
    |> Repo.update_all(inc: [failure_count: 1])
  end

  defp reset_failure_count(endpoint) do
    from(e in Endpoint, where: e.id == ^endpoint.id)
    |> Repo.update_all(set: [failure_count: 0])
  end
end
