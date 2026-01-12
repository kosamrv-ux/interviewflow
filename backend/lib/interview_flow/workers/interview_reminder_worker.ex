defmodule InterviewFlow.Workers.InterviewReminderWorker do
  @moduledoc """
  Sends email and/or Slack reminders to interviewers and candidates
  before their scheduled interview sessions.

  Triggered by `ScheduleReminderWorker` which enqueues reminder jobs
  at 24h and 1h before each interview. This worker handles the actual
  delivery and records delivery status on the Interview record.
  """

  use Oban.Worker,
    queue: :notifications,
    max_attempts: 5

  require Logger

  alias InterviewFlow.{Repo, Interviews}
  alias InterviewFlow.Interviews.Interview

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"interview_id" => id, "reminder_type" => reminder_type}}) do
    case Repo.get(Interview, id) do
      nil ->
        Logger.warning("interview_reminder_worker: interview not found", interview_id: id)
        {:cancel, "interview not found"}

      %Interview{status: status} when status in ["cancelled", "completed"] ->
        Logger.info("interview_reminder_worker: skipping #{status} interview", interview_id: id)
        :ok

      interview ->
        interview = Repo.preload(interview, [:interviewer, application: [:candidate, :job]])
        send_reminders(interview, reminder_type)
    end
  end

  # ── Private ──────────────────────────────────────────────────────────────

  defp send_reminders(interview, reminder_type) do
    results = [
      send_interviewer_reminder(interview, reminder_type),
      send_candidate_reminder(interview, reminder_type)
    ]

    errors = Enum.filter(results, &match?({:error, _}, &1))

    if errors == [] do
      Logger.info("interview_reminder_worker: reminders sent",
        interview_id: interview.id,
        type: reminder_type
      )

      :ok
    else
      Logger.error("interview_reminder_worker: some reminders failed",
        interview_id: interview.id,
        errors: inspect(errors)
      )

      {:error, "partial reminder failure"}
    end
  end

  defp send_interviewer_reminder(interview, reminder_type) do
    user = interview.interviewer
    label = reminder_label(reminder_type)

    Logger.info("interview_reminder_worker: sending interviewer email",
      user_id: user.id,
      label: label
    )

    InterviewFlow.Mailer.send_interview_reminder(%{
      to: user.email,
      name: user.full_name,
      role: :interviewer,
      interview: interview,
      reminder_type: reminder_type
    })
  end

  defp send_candidate_reminder(interview, reminder_type) do
    candidate = interview.application.candidate
    label = reminder_label(reminder_type)

    Logger.info("interview_reminder_worker: sending candidate email",
      candidate_id: candidate.id,
      label: label
    )

    InterviewFlow.Mailer.send_interview_reminder(%{
      to: candidate.email,
      name: candidate.full_name,
      role: :candidate,
      interview: interview,
      reminder_type: reminder_type
    })
  end

  defp reminder_label("24h"), do: "24-hour"
  defp reminder_label("1h"), do: "1-hour"
  defp reminder_label(other), do: other
end
