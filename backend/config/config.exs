import Config

config :interview_flow,
  ecto_repos: [InterviewFlow.Repo],
  generators: [timestamp_type: :utc_datetime_usec, binary_id: true]

config :interview_flow, InterviewFlowWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: InterviewFlowWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: InterviewFlow.PubSub,
  live_view: [signing_salt: "interview_live_salt"]

# Configure Guardian for JWT
config :interview_flow, InterviewFlow.Auth.Guardian,
  issuer: "interview_flow",
  ttl: {1, :hour},
  secret_key: System.get_env("GUARDIAN_SECRET_KEY") || "dev_guardian_secret"

# Configure Oban background jobs
config :interview_flow, Oban,
  repo: InterviewFlow.Repo,
  plugins: [
    Oban.Plugins.Pruner,
    {Oban.Plugins.Cron,
     crontab: [
       # Purge expired video sessions daily at 3am
       {"0 3 * * *", InterviewFlow.Workers.PurgeExpiredSessionsWorker},
       # Send upcoming interview reminders every 15 minutes
       {"*/15 * * * *", InterviewFlow.Workers.ScheduleReminderWorker}
     ]}
  ],
  queues: [
    default: 10,
    scoring: 5,
    notifications: 20,
    calendar_sync: 3
  ]

# Tesla HTTP client for external API calls
config :tesla, adapter: Tesla.Adapter.Hackney

# Telemetry
config :interview_flow, InterviewFlow.Telemetry,
  metrics: []

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :user_id, :company_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
