defmodule InterviewFlow.Workers.TriggerScoringWorker do
  @moduledoc """
  Oban worker that triggers AI scoring after a video session ends.
  Calls the Python FastAPI scoring service and persists the result.
  """

  use Oban.Worker,
    queue: :scoring,
    max_attempts: 3,
    unique: [period: 300, fields: [:args]]

  alias InterviewFlow.Repo
  alias InterviewFlow.Interviews.VideoSession
  alias InterviewFlow.Scoring
  alias InterviewFlow.Scoring.AiScore

  require Logger

  @impl true
  def perform(%Oban.Job{args: %{"session_id" => session_id}}) do
    Logger.info("Triggering AI scoring for session #{session_id}")

    with {:ok, session} <- load_session(session_id),
         {:ok, application} <- load_application(session),
         {:ok, request} <- build_scoring_request(session, application),
         {:ok, score_data} <- call_ai_service(request),
         {:ok, _score} <- persist_score(application, session, score_data) do
      Logger.info("AI scoring complete for session #{session_id}, score: #{score_data["composite_score"]}")
      :ok
    else
      {:error, :session_not_found} ->
        Logger.warning("Session #{session_id} not found for scoring — skipping")
        :ok

      {:error, :no_transcript} ->
        Logger.info("Session #{session_id} has no transcript — skipping scoring")
        :ok

      {:error, reason} ->
        Logger.error("AI scoring failed for session #{session_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp load_session(session_id) do
    case Repo.get(VideoSession, session_id) do
      nil -> {:error, :session_not_found}
      session -> {:ok, session}
    end
  end

  defp load_application(session) do
    session = Repo.preload(session, interview: [application: [job: [], candidate: []]])

    case session.interview.application do
      nil -> {:error, :application_not_found}
      application -> {:ok, application}
    end
  end

  defp build_scoring_request(session, application) do
    if is_nil(session.transcript_url) do
      {:error, :no_transcript}
    else
      job = application.job

      request = %{
        session_id: session.id,
        application_id: application.id,
        job_title: job.title,
        transcript_url: session.transcript_url,
        rubric: job.scoring_rubric,
        prompt_version: "v2.1"
      }

      {:ok, request}
    end
  end

  defp call_ai_service(request) do
    ai_url = Application.get_env(:interview_flow, :ai_service_url, "http://localhost:8000")
    client = build_client()

    case Tesla.post(client, "#{ai_url}/score", request) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        Logger.error("AI service returned #{status}: #{inspect(body)}")
        {:error, {:ai_service_error, status}}

      {:error, reason} ->
        {:error, {:network_error, reason}}
    end
  end

  defp persist_score(application, session, score_data) do
    attrs = %{
      application_id: application.id,
      video_session_id: session.id,
      composite_score: score_data["composite_score"],
      breakdown: score_data["breakdown"],
      strengths: score_data["strengths"],
      areas_for_growth: score_data["areas_for_growth"],
      recommended_action: score_data["recommended_action"],
      confidence: score_data["confidence"],
      model_version: score_data["model"],
      processing_ms: score_data["processing_ms"],
      prompt_version: score_data["prompt_version"] || "v2.1",
      status: "completed"
    }

    Scoring.upsert_score(attrs)
  end

  defp build_client do
    secret = Application.get_env(:interview_flow, :ai_service_secret, "dev-secret")

    Tesla.client([
      {Tesla.Middleware.Headers, [{"x-service-secret", secret}]},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Retry,
       delay: 500,
       max_retries: 2,
       should_retry: fn
         {:ok, %{status: status}} when status in [429, 500, 502, 503] -> true
         {:error, _} -> true
         _ -> false
       end}
    ])
  end
end
