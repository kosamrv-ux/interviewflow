defmodule InterviewFlow.Workers.ScheduleReminderWorker do
  @moduledoc """
  Oban worker that sends interview reminders.
  Runs every 15 minutes via cron; finds interviews due for reminders.

  Reminder schedule:
  - 24 hours before: sent to candidate and all interviewers
  - 1 hour before: sent to candidate and all interviewers
  """

  use Oban.Worker, queue: :notifications, max_attempts: 3

  alias InterviewFlow.Repo
  alias InterviewFlow.Interviews.Interview
  import Ecto.Query

  require Logger

  @impl true
  def perform(_job) do
    now = DateTime.utc_now()
    window_24h = DateTime.add(now, 24 * 60 * 60, :second)
    window_1h = DateTime.add(now, 60 * 60, :second)
    buffer = DateTime.add(now, 15 * 60, :second)  # 15-minute cron buffer

    # Find interviews that need 24h reminders
    remind_24h =
      Interview
      |> where([i], i.status == "scheduled")
      |> where([i], i.scheduled_at >= ^window_24h and i.scheduled_at < ^DateTime.add(window_24h, 15 * 60, :second))
      |> preload(application: [:candidate], interview_interviewers: [:user])
      |> Repo.all()

    # Find interviews that need 1h reminders
    remind_1h =
      Interview
      |> where([i], i.status == "scheduled")
      |> where([i], i.scheduled_at >= ^window_1h and i.scheduled_at < ^DateTime.add(window_1h, 15 * 60, :second))
      |> preload(application: [:candidate], interview_interviewers: [:user])
      |> Repo.all()

    Enum.each(remind_24h, &send_reminder(&1, :hours_24))
    Enum.each(remind_1h, &send_reminder(&1, :hours_1))

    Logger.info("Reminder check: #{length(remind_24h)} 24h reminders, #{length(remind_1h)} 1h reminders")
    :ok
  end

  defp send_reminder(interview, timing) do
    time_label = if timing == :hours_24, do: "24 hours", else: "1 hour"
    Logger.info("Sending #{time_label} reminder for interview #{interview.id}")

    # In a full implementation this would call Swoosh to send emails.
    # The email template includes the candidate's name, interview time,
    # joining link, and any special instructions.
    :ok
  end
end
