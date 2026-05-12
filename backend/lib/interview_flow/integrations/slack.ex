defmodule InterviewFlow.Integrations.Slack do
  @moduledoc """
  Slack notification integration.

  Sends notification messages to Slack when key events occur:
  - Interview scheduled → recruiter channel
  - Interview completed with score → recruiter channel + hiring manager DM
  - Candidate ranked #1 for a job → hiring manager DM
  - Interview no-show → immediate recruiter alert

  ## Configuration

  Set per organization in org.settings["slack"]:
    - bot_token: Slack Bot OAuth token (xoxb-...)
    - default_channel: default channel ID or name (e.g. "#recruiting")
    - hiring_manager_channel: optional separate channel for HM updates

  ## Blocks vs Text fallback

  All messages are sent as Block Kit blocks for rich formatting.
  A `text` fallback is always included for notification previews and accessibility.
  """

  require Logger

  @api_base "https://slack.com/api"

  @doc """
  Sends an interview scheduled notification to the configured recruiter channel.
  """
  def notify_interview_scheduled(org, interview, candidate, job) do
    with {:ok, config} <- get_config(org) do
      blocks = interview_scheduled_blocks(interview, candidate, job)
      text = "Interview scheduled: #{candidate.name} for #{job.title} on #{format_dt(interview.scheduled_at)}"

      post_message(config, config["default_channel"], text, blocks)
    end
  end

  @doc """
  Sends a scoring completed notification with composite score.
  """
  def notify_scoring_completed(org, candidate, job, score_data) do
    with {:ok, config} <- get_config(org) do
      channel = config["default_channel"]
      emoji = score_emoji(score_data.composite_score)

      blocks = scoring_completed_blocks(candidate, job, score_data, emoji)
      text = "#{emoji} Scoring complete: #{candidate.name} scored #{round(score_data.composite_score)}/100 for #{job.title}"

      post_message(config, channel, text, blocks)
    end
  end

  @doc """
  Sends an urgent no-show alert.
  """
  def notify_no_show(org, interview, candidate, job) do
    with {:ok, config} <- get_config(org) do
      channel = config["default_channel"]
      text = ":warning: No-show: #{candidate.name} did not join their interview for #{job.title}"

      blocks = [
        %{
          "type" => "section",
          "text" => %{
            "type" => "mrkdwn",
            "text" => ":warning: *No-Show Alert*\n#{candidate.name} did not join their interview for *#{job.title}*."
          }
        },
        %{
          "type" => "context",
          "elements" => [%{"type" => "mrkdwn", "text" => "Scheduled: #{format_dt(interview.scheduled_at)}"}]
        }
      ]

      post_message(config, channel, text, blocks)
    end
  end

  ## Private

  defp post_message(config, channel, text, blocks) do
    token = config["bot_token"]
    body = Jason.encode!(%{channel: channel, text: text, blocks: blocks})
    headers = [{"Authorization", "Bearer #{token}"}, {"Content-Type", "application/json"}]

    case HTTPoison.post("#{@api_base}/chat.postMessage", body, headers) do
      {:ok, %{status_code: 200, body: resp_body}} ->
        case Jason.decode!(resp_body) do
          %{"ok" => true} ->
            :ok

          %{"ok" => false, "error" => error} ->
            Logger.error("[Slack] chat.postMessage failed: #{error}")
            {:error, error}
        end

      {:ok, %{status_code: code, body: b}} ->
        Logger.error("[Slack] HTTP #{code}: #{b}")
        {:error, "HTTP #{code}"}

      {:error, reason} ->
        Logger.error("[Slack] network error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp get_config(org) do
    case get_in(org.settings, ["slack", "bot_token"]) do
      nil -> {:error, "Slack not configured for this organization"}
      _ -> {:ok, org.settings["slack"]}
    end
  end

  defp interview_scheduled_blocks(interview, candidate, job) do
    [
      %{
        "type" => "header",
        "text" => %{"type" => "plain_text", "text" => "Interview Scheduled"}
      },
      %{
        "type" => "section",
        "fields" => [
          %{"type" => "mrkdwn", "text" => "*Candidate*\n#{candidate.name}"},
          %{"type" => "mrkdwn", "text" => "*Role*\n#{job.title}"},
          %{"type" => "mrkdwn", "text" => "*Time*\n#{format_dt(interview.scheduled_at)}"},
          %{"type" => "mrkdwn", "text" => "*Duration*\n#{interview.duration_minutes} min"}
        ]
      },
      %{
        "type" => "actions",
        "elements" => [
          %{
            "type" => "button",
            "text" => %{"type" => "plain_text", "text" => "View Interview"},
            "url" => "https://app.interviewflow.io/interviews/#{interview.id}",
            "style" => "primary"
          }
        ]
      }
    ]
  end

  defp scoring_completed_blocks(candidate, job, score_data, emoji) do
    [
      %{
        "type" => "section",
        "text" => %{
          "type" => "mrkdwn",
          "text" => "#{emoji} *AI Scoring Complete*\n#{candidate.name} — *#{job.title}*"
        }
      },
      %{
        "type" => "section",
        "fields" =>
          [%{"type" => "mrkdwn", "text" => "*Composite Score*\n#{round(score_data.composite_score)}/100"}] ++
            Enum.map(score_data.dimensions, fn {k, v} ->
              %{"type" => "mrkdwn", "text" => "*#{humanize(k)}*\n#{round(v)}/100"}
            end)
      }
    ]
  end

  defp score_emoji(score) when score >= 80, do: ":star-struck:"
  defp score_emoji(score) when score >= 60, do: ":thumbsup:"
  defp score_emoji(score) when score >= 40, do: ":neutral_face:"
  defp score_emoji(_), do: ":thumbsdown:"

  defp format_dt(nil), do: "N/A"
  defp format_dt(%DateTime{} = dt), do: Calendar.strftime(dt, "%b %d, %Y at %I:%M %p UTC")
  defp format_dt(%NaiveDateTime{} = ndt), do: Calendar.strftime(ndt, "%b %d, %Y at %I:%M %p")

  defp humanize(key), do: key |> to_string() |> String.replace("_", " ") |> String.capitalize()
end
