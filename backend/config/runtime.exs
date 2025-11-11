import Config

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise "DATABASE_URL environment variable is required in production"

  config :interview_flow, InterviewFlow.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    ssl: true,
    ssl_opts: [verify: :verify_none]

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise "SECRET_KEY_BASE environment variable is required in production"

  host = System.get_env("PHX_HOST") || raise "PHX_HOST environment variable is required"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :interview_flow, InterviewFlowWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base

  guardian_secret =
    System.get_env("GUARDIAN_SECRET_KEY") ||
      raise "GUARDIAN_SECRET_KEY environment variable is required"

  config :interview_flow, InterviewFlow.Auth.Guardian,
    secret_key: guardian_secret

  redis_url =
    System.get_env("REDIS_URL") ||
      raise "REDIS_URL environment variable is required in production"

  config :interview_flow, :redis_url, redis_url
  config :interview_flow, :ai_service_url, System.get_env("AI_SERVICE_URL") || raise("AI_SERVICE_URL required")
  config :interview_flow, :ai_service_secret, System.get_env("AI_SERVICE_SECRET") || raise("AI_SERVICE_SECRET required")

  config :interview_flow, :twilio,
    account_sid: System.get_env("TWILIO_ACCOUNT_SID") || raise("TWILIO_ACCOUNT_SID required"),
    auth_token: System.get_env("TWILIO_AUTH_TOKEN") || raise("TWILIO_AUTH_TOKEN required"),
    ice_ttl: String.to_integer(System.get_env("TWILIO_ICE_TTL") || "86400")
end
