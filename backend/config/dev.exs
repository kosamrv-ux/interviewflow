import Config

config :interview_flow, InterviewFlow.Repo,
  username: "interviewflow",
  password: "interviewflow",
  hostname: "localhost",
  database: "interviewflow_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :interview_flow, InterviewFlowWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev_secret_key_base_min_64_chars_replace_in_production_please_dont_use",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:default, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:default, ~w(--watch)]}
  ]

config :interview_flow, InterviewFlowWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/interview_flow_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

config :interview_flow, :ai_service_url, System.get_env("AI_SERVICE_URL") || "http://localhost:8000"
config :interview_flow, :redis_url, System.get_env("REDIS_URL") || "redis://localhost:6379/0"

config :logger, level: :debug

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
config :phoenix_live_view, :debug_heex_annotations, true
