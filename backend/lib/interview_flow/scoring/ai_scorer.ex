defmodule InterviewFlow.Scoring.AiScorer do
  @moduledoc """
  Client for the Python AI scoring microservice.

  Sends interview transcript and coding challenge data to the scoring
  API and persists the resulting `AiScore` record. Implements retry logic
  with exponential backoff for transient HTTP failures.
  """

  require Logger

  alias InterviewFlow.{Repo, Scoring}
  alias InterviewFlow.Scoring.AiScore
  alias Tesla.Middleware

  @max_retries 3
  @base_delay_ms 500

  @doc """
  Requests an AI score for the given application.

  Fetches the associated video session transcript and coding challenge
  snapshots, then submits them to the scoring service.

  Returns `{:ok, ai_score}` or `{:error, reason}`.
  """
  @spec score_application(Ecto.UUID.t()) :: {:ok, AiScore.t()} | {:error, any()}
  def score_application(application_id) do
    Logger.info("ai_scorer: scoring application", application_id: application_id)

    with {:ok, payload} <- build_scoring_payload(application_id),
         {:ok, result} <- call_scoring_service(payload),
         {:ok, ai_score} <- persist_score(application_id, result) do
      Logger.info("ai_scorer: score persisted",
        application_id: application_id,
        score: ai_score.composite_score
      )

      {:ok, ai_score}
    else
      {:error, reason} = err ->
        Logger.error("ai_scorer: scoring failed",
          application_id: application_id,
          reason: inspect(reason)
        )

        err
    end
  end

  # ── Payload builder ──────────────────────────────────────────────────────

  defp build_scoring_payload(application_id) do
    case Scoring.load_scoring_context(application_id) do
      nil -> {:error, :application_not_found}
      ctx -> {:ok, ctx}
    end
  end

  # ── HTTP client ──────────────────────────────────────────────────────────

  defp call_scoring_service(payload, attempt \\ 1) do
    client = build_client()

    case Tesla.post(client, "/score", payload) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status}} when status in [429, 500, 502, 503, 504] and attempt < @max_retries ->
        delay = @base_delay_ms * Integer.pow(2, attempt - 1)
        Logger.warning("ai_scorer: retrying after #{status}", attempt: attempt)
        Process.sleep(delay)
        call_scoring_service(payload, attempt + 1)

      {:ok, %{status: status, body: body}} ->
        {:error, %{status: status, body: body}}

      {:error, reason} when attempt < @max_retries ->
        delay = @base_delay_ms * Integer.pow(2, attempt - 1)
        Logger.warning("ai_scorer: network error, retrying", reason: inspect(reason))
        Process.sleep(delay)
        call_scoring_service(payload, attempt + 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_client do
    base_url = Application.get_env(:interview_flow, :ai_service_url, "http://ai-service:8000")
    api_key = Application.get_env(:interview_flow, :ai_service_api_key, "")

    Tesla.client([
      {Middleware.BaseUrl, base_url},
      {Middleware.Headers, [{"x-api-key", api_key}, {"content-type", "application/json"}]},
      {Middleware.JSON, []},
      {Middleware.Timeout, timeout: 30_000}
    ])
  end

  # ── Persistence ──────────────────────────────────────────────────────────

  defp persist_score(application_id, result) do
    attrs = %{
      application_id: application_id,
      composite_score: result["composite_score"],
      communication_score: result["dimension_scores"]["communication"],
      technical_score: result["dimension_scores"]["technical"],
      problem_solving_score: result["dimension_scores"]["problem_solving"],
      cultural_fit_score: result["dimension_scores"]["cultural_fit"],
      summary: result["summary"],
      strengths: result["strengths"],
      concerns: result["concerns"],
      model_version: result["model_version"],
      scored_at: DateTime.utc_now()
    }

    Scoring.upsert_score(attrs)
  end
end
