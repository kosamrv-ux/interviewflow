defmodule InterviewFlow.Workers.QueueConfig do
  @moduledoc """
  Oban queue configuration, concurrency tuning, and dead-letter handling
  for the InterviewFlow background job system.

  ## Queue topology

  | Queue       | Concurrency | Purpose                                       |
  |-------------|-------------|-----------------------------------------------|
  | scoring     | 20          | AI scoring calls (I/O-bound, high parallelism)|
  | mailer      | 10          | Transactional emails via SendGrid             |
  | default     | 5           | Catch-all; batch scheduling, misc workers     |
  | exports     | 2           | CSV/PDF exports (CPU-bound; keep low)         |
  | maintenance | 1           | Session purge, audit log archival             |

  ## Retry strategy
  Oban uses exponential back-off by default.  Workers that call external
  services (AI scorer, Twilio, SendGrid) are configured with snooze guards
  to avoid thundering herd on downstream rate limits.

  ## Dead-letter handling
  Jobs that exhaust all attempts land in state="discarded".  The
  `DeadLetterReporter` worker polls this table every 10 min and pages
  on-call via PagerDuty when the discard count exceeds thresholds.
  """

  @queues [
    scoring:     [limit: 20],
    mailer:      [limit: 10],
    default:     [limit: 5],
    exports:     [limit: 2],
    maintenance: [limit: 1]
  ]

  @doc "Returns queue definitions for Oban config in application.ex."
  def queues, do: @queues

  @doc """
  Returns Oban plugin configuration list.  Included plugins:

  - `Oban.Pro.Plugins.DynamicPruner`: keeps 7 days of completed/cancelled
    jobs for audit; discarded jobs retained 30 days.
  - `Oban.Plugins.Cron`: scheduled recurring jobs.
  - `Oban.Plugins.Lifeline`: rescues orphaned executing jobs after 5 min.
  - `Oban.Plugins.Stager`: promotes scheduled jobs to available on time.
  """
  def plugins do
    [
      {Oban.Plugins.Pruner,
       max_age: 7 * 24 * 60 * 60,
       limit: 5_000},

      {Oban.Plugins.Lifeline,
       rescue_after: :timer.minutes(5)},

      {Oban.Plugins.Stager, []},

      {Oban.Plugins.Cron,
       crontab: crontab()}
    ]
  end

  @doc "Crontab entries — maps schedule to worker module."
  def crontab do
    [
      # Batch scoring: catch sessions missed by real-time trigger
      {"*/15 * * * *", InterviewFlow.Workers.BatchScoringWorker},

      # Send interview reminders for sessions starting in ~24h
      {"0 * * * *", InterviewFlow.Workers.ScheduleReminderWorker},

      # Purge expired sessions and blacklisted tokens
      {"0 3 * * *", InterviewFlow.Workers.PurgeExpiredSessionsWorker},

      # Archive audit log entries older than 90 days to GCS cold storage
      {"0 2 * * 0", InterviewFlow.Workers.ArchiveAuditLogWorker},

      # Dead-letter sweep: page on-call if discard rate exceeds threshold
      {"*/10 * * * *", InterviewFlow.Workers.DeadLetterReporter}
    ]
  end
end
