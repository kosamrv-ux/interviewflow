defmodule InterviewFlowWeb.IntegrationWebhookController do
  @moduledoc """
  Handles incoming webhook events from third-party integrations.

  Routes:
    POST /integrations/greenhouse/webhook   — Greenhouse ATS events
    POST /integrations/slack/webhook        — Slack events API (URL verification + events)

  All endpoints verify the incoming signature before processing.
  Unknown event types are logged and acknowledged with 200 (don't retry, don't error).
  """

  use InterviewFlowWeb, :controller

  alias InterviewFlow.Integrations.Greenhouse
  alias InterviewFlow.Organizations

  require Logger

  ## Greenhouse

  def greenhouse(conn, _params) do
    raw_body = conn.assigns[:raw_body] || ""
    signature = get_req_header(conn, "signature") |> List.first("")
    secret = Application.get_env(:interview_flow, :greenhouse_webhook_secret, "")

    if Greenhouse.verify_webhook_signature(raw_body, signature, secret) do
      event = Jason.decode!(raw_body)
      handle_greenhouse_event(event)
      send_resp(conn, :ok, "")
    else
      Logger.warning("[Webhook:Greenhouse] invalid signature, rejecting")
      send_resp(conn, :unauthorized, "")
    end
  end

  ## Slack

  def slack(conn, %{"type" => "url_verification", "challenge" => challenge}) do
    # Slack sends this to verify the webhook URL
    json(conn, %{challenge: challenge})
  end

  def slack(conn, %{"type" => "event_callback"} = payload) do
    raw_body = conn.assigns[:raw_body] || ""
    timestamp = get_req_header(conn, "x-slack-request-timestamp") |> List.first("")
    signature = get_req_header(conn, "x-slack-signature") |> List.first("")

    if verify_slack_signature(raw_body, timestamp, signature) do
      handle_slack_event(payload["event"] || %{})
      send_resp(conn, :ok, "")
    else
      Logger.warning("[Webhook:Slack] invalid signature")
      send_resp(conn, :unauthorized, "")
    end
  end

  def slack(conn, _params) do
    send_resp(conn, :ok, "")
  end

  ## Private — Greenhouse event handlers

  defp handle_greenhouse_event(%{"action" => "application_created", "payload" => payload}) do
    Logger.info("[Webhook:Greenhouse] application_created: #{payload["id"]}")
    # Queue background job to import candidate
    %{greenhouse_application_id: payload["id"]}
    |> InterviewFlow.Workers.GreenhouseImportWorker.new()
    |> Oban.insert()
  end

  defp handle_greenhouse_event(%{"action" => "candidate_updated", "payload" => payload}) do
    Logger.info("[Webhook:Greenhouse] candidate_updated: #{payload["candidate"]["id"]}")
    # Sync updates back to our local candidate record if we have them
    :ok
  end

  defp handle_greenhouse_event(%{"action" => action}) do
    Logger.debug("[Webhook:Greenhouse] unhandled event: #{action}")
    :ok
  end

  ## Private — Slack event handlers

  defp handle_slack_event(%{"type" => "app_mention"} = event) do
    Logger.info("[Webhook:Slack] app_mention in channel #{event["channel"]}")
    :ok
  end

  defp handle_slack_event(%{"type" => type}) do
    Logger.debug("[Webhook:Slack] unhandled event type: #{type}")
    :ok
  end

  defp handle_slack_event(_), do: :ok

  ## Slack signature verification

  defp verify_slack_signature(body, timestamp, "v0=" <> hash) do
    secret = Application.get_env(:interview_flow, :slack_signing_secret, "")
    base_string = "v0:#{timestamp}:#{body}"
    expected = :crypto.mac(:hmac, :sha256, secret, base_string) |> Base.encode16(case: :lower)
    Plug.Crypto.secure_compare(expected, hash)
  end

  defp verify_slack_signature(_, _, _), do: false
end
