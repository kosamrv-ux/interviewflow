defmodule InterviewFlow.Metrics do
  @moduledoc """
  Prometheus-compatible metrics instrumentation for InterviewFlow.

  Exposes metrics via `:telemetry` events that are collected by the
  `PromEx` library (or a custom Prometheus scraper mounted at /metrics).

  ## Metrics exposed

  ### Business Metrics (Custom)
  - `interviewflow_interviews_scheduled_total` — counter, labels: type
  - `interviewflow_applications_advanced_total` — counter, labels: from_stage, to_stage
  - `interviewflow_ai_score_latency_seconds`  — histogram, labels: model_version
  - `interviewflow_active_video_sessions`     — gauge
  - `interviewflow_candidates_hired_total`    — counter, labels: department

  ### HTTP Metrics (via Phoenix)
  - `phoenix_http_request_duration_milliseconds` — histogram, labels: method, route, status

  ### Database Metrics (via Ecto)
  - `ecto_query_total_time_milliseconds` — histogram, labels: source
  """

  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    [
      Event.build(
        :interviewflow_business_events,
        [
          counter(
            "interviewflow.interviews.scheduled.total",
            event_name: [:interviewflow, :interview, :scheduled],
            measurement: :count,
            description: "Total interviews scheduled",
            tags: [:interview_type]
          ),
          counter(
            "interviewflow.applications.advanced.total",
            event_name: [:interviewflow, :application, :advanced],
            measurement: :count,
            description: "Total pipeline stage advancements",
            tags: [:from_stage, :to_stage]
          ),
          counter(
            "interviewflow.candidates.hired.total",
            event_name: [:interviewflow, :candidate, :hired],
            measurement: :count,
            description: "Total candidates marked as hired",
            tags: [:department]
          ),
          distribution(
            "interviewflow.ai_score.latency.seconds",
            event_name: [:interviewflow, :ai_score, :completed],
            measurement: :duration,
            unit: {:native, :second},
            description: "AI scoring latency in seconds",
            tags: [:model_version],
            reporter_options: [
              buckets: [0.5, 1.0, 2.0, 5.0, 10.0, 30.0, 60.0]
            ]
          )
        ]
      )
    ]
  end

  @impl true
  def polling_metrics(_opts) do
    [
      Polling.build(
        :interviewflow_active_sessions,
        5_000,
        {__MODULE__, :active_session_count, []},
        [
          last_value(
            "interviewflow.active_video_sessions",
            event_name: [:interviewflow, :active_sessions, :count],
            description: "Number of currently active video sessions",
            measurement: :count
          )
        ]
      )
    ]
  end

  @doc "Called by polling metrics — returns current active video session count."
  def active_session_count do
    count = InterviewFlow.Interviews.count_active_sessions()
    :telemetry.execute([:interviewflow, :active_sessions, :count], %{count: count}, %{})
  end

  # ── Telemetry emit helpers ────────────────────────────────────────────────

  @doc "Emits a telemetry event when an interview is scheduled."
  def emit_interview_scheduled(interview_type) do
    :telemetry.execute(
      [:interviewflow, :interview, :scheduled],
      %{count: 1},
      %{interview_type: interview_type}
    )
  end

  @doc "Emits a telemetry event when an application advances stages."
  def emit_stage_advanced(from_stage, to_stage) do
    :telemetry.execute(
      [:interviewflow, :application, :advanced],
      %{count: 1},
      %{from_stage: from_stage, to_stage: to_stage}
    )
  end

  @doc "Emits a telemetry event when AI scoring completes."
  def emit_ai_score_completed(duration_native, model_version) do
    :telemetry.execute(
      [:interviewflow, :ai_score, :completed],
      %{duration: duration_native},
      %{model_version: model_version}
    )
  end

  @doc "Emits a telemetry event when a candidate is hired."
  def emit_candidate_hired(department) do
    :telemetry.execute(
      [:interviewflow, :candidate, :hired],
      %{count: 1},
      %{department: department}
    )
  end
end
