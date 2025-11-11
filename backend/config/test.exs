import Config

config :interview_flow, InterviewFlow.Repo,
  username: "interviewflow",
  password: "interviewflow",
  hostname: "localhost",
  database: "interviewflow_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :interview_flow, InterviewFlowWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test_secret_key_base_min_64_chars_not_for_production_at_all_really",
  server: false

config :interview_flow, InterviewFlow.Auth.Guardian,
  secret_key: "test_guardian_secret_key_not_for_production"

# Disable async Oban in tests
config :interview_flow, Oban, testing: :inline

config :interview_flow, :ai_service_url, "http://localhost:8000"
config :interview_flow, :redis_url, "redis://localhost:6379/0"

# Faster bcrypt rounds in tests
config :bcrypt_elixir, :log_rounds, 1

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime
