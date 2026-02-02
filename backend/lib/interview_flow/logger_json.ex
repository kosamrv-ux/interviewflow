defmodule InterviewFlow.LoggerJSON do
  @moduledoc """
  Configures structured JSON logging with correlation fields.

  In production, all log output is emitted as newline-delimited JSON (NDJSON)
  with the following fields on every line:

    - `timestamp`   — ISO-8601 UTC
    - `level`       — debug | info | warning | error
    - `message`     — the log message string
    - `request_id`  — from Logger metadata (set by RequestId plug)
    - `user_id`     — from Logger metadata (set by SetCurrentUser plug)
    - `company_id`  — from Logger metadata (set by SetCurrentUser plug)
    - `service`     — always "interview_flow_backend"
    - `env`         — from MIX_ENV

  Additional structured fields can be added by passing a keyword list or map
  as the second argument to Logger calls:

      Logger.info("scoring complete",
        application_id: app.id,
        score: 0.87,
        duration_ms: 423
      )

  This enables log-based alerting and dashboards in Datadog / CloudWatch.
  """

  @service "interview_flow_backend"
  @env Mix.env() |> to_string()

  @doc """
  Returns the LoggerJSON formatter configuration for use in config/runtime.exs.
  """
  def formatter_config do
    {LoggerJSON.Formatters.BasicLogger,
     metadata: [:request_id, :user_id, :company_id, :application_id, :job_id]}
  end

  @doc """
  Adds standard service metadata to Logger so it appears in every log line.
  Call this from your Application.start/2.
  """
  def setup do
    Logger.metadata(service: @service, env: @env)
  end

  @doc """
  Attaches a telemetry handler that logs Phoenix request events with
  structured fields: method, path, status, duration_ms, request_id.
  """
  def attach_phoenix_logger do
    :telemetry.attach(
      "interviewflow-phoenix-requests",
      [:phoenix, :endpoint, :stop],
      &__MODULE__.handle_phoenix_event/4,
      nil
    )
  end

  def handle_phoenix_event(
        _event,
        %{duration: duration},
        %{conn: conn, route: route},
        _config
      ) do
    duration_ms = System.convert_time_unit(duration, :native, :millisecond)

    Logger.info("http_request",
      method: conn.method,
      path: conn.request_path,
      route: route,
      status: conn.status,
      duration_ms: duration_ms,
      request_id: conn.assigns[:request_id]
    )
  end

  def handle_phoenix_event(_event, _measurements, _meta, _config), do: :ok
end
