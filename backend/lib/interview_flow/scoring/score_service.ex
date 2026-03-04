defmodule InterviewFlow.Scoring.ScoreService do
  @moduledoc """
  Unified façade for all AI scoring operations.

  Extracted from the scattered scoring logic that previously lived in
  multiple controllers and workers. Provides a single, well-tested entry
  point for triggering, retrieving, and overriding AI scores.

  ## Responsibilities
  - Coordinate the scoring pipeline (payload build → AI call → persist → rank)
  - Emit telemetry events for observability
  - Enforce business rules (e.g., no re-scoring within 30 minutes)

  This extraction follows ADR-005 (see docs/adrs/ADR-005.md).
  """

  require Logger

  alias InterviewFlow.{Repo, Scoring}
  alias InterviewFlow.Scoring.{AiScorer, Ranking, AiScore}
  alias InterviewFlow.Candidates.Application
  alias InterviewFlow.Metrics

  @min_rescore_interval_seconds 30 * 60

  @doc """
  Triggers AI scoring for an application.

  Guards against redundant re-scoring: if a score was computed within the
  last #{div(@min_rescore_interval_seconds, 60)} minutes, returns the existing
  score unless `force: true` is passed.

  Emits `:interviewflow, :ai_score, :completed` telemetry on success.

  Returns `{:ok, ai_score}` or `{:error, reason}`.
  """
  @spec score(Ecto.UUID.t(), keyword()) :: {:ok, AiScore.t()} | {:error, any()}
  def score(application_id, opts \\ []) do
    force = Keyword.get(opts, :force, false)

    with {:ok, app} <- fetch_application(application_id),
         :ok <- check_rescore_interval(app, force) do
      start = System.monotonic_time(:native)

      case AiScorer.score_application(application_id) do
        {:ok, ai_score} = result ->
          duration = System.monotonic_time(:native) - start
          Metrics.emit_ai_score_completed(duration, ai_score.model_version)
          Ranking.rerank_job(app.job_id)
          result

        {:error, _} = err ->
          err
      end
    end
  end

  @doc """
  Overrides an AI score dimension with a human reviewer's judgment.

  Persists the override reason for audit trail purposes.
  Only admin and recruiter roles can call this (enforced at the controller level).
  """
  @spec override(Ecto.UUID.t(), map(), map()) :: {:ok, AiScore.t()} | {:error, any()}
  def override(score_id, reviewer, override_attrs) do
    with {:ok, score} <- fetch_score(score_id) do
      Logger.info("score_service: manual override",
        score_id: score_id,
        reviewer_id: reviewer.id,
        fields: Map.keys(override_attrs)
      )

      score
      |> AiScore.override_changeset(Map.put(override_attrs, :overridden_by, reviewer.id))
      |> Repo.update()
    end
  end

  @doc """
  Returns the latest score for an application, or nil.
  Result is cached at warm TTL (300 s) to avoid repeated DB reads on the
  application detail page which polls every 5 s during active scoring.
  """
  @spec latest_score(Ecto.UUID.t()) :: AiScore.t() | nil
  def latest_score(application_id) do
    cache_key = InterviewFlow.Cache.agg_key("latest_score", application_id)

    case InterviewFlow.Cache.get(cache_key) do
      {:ok, score} ->
        score

      :miss ->
        score = Scoring.latest_score_for_application(application_id)
        if score, do: InterviewFlow.Cache.put(cache_key, score, InterviewFlow.Cache.ttl(:warm))
        score
    end
  end

  @doc "Returns all scores for an application (including overrides), newest first."
  @spec score_history(Ecto.UUID.t()) :: [AiScore.t()]
  def score_history(application_id) do
    Scoring.list_scores_for_application(application_id)
  end

  # ── Private helpers ──────────────────────────────────────────────────────

  defp fetch_application(id) do
    case Repo.get(Application, id) do
      nil -> {:error, :application_not_found}
      app -> {:ok, app}
    end
  end

  defp fetch_score(id) do
    case Repo.get(AiScore, id) do
      nil -> {:error, :score_not_found}
      score -> {:ok, score}
    end
  end

  defp check_rescore_interval(_app, true), do: :ok

  defp check_rescore_interval(app, false) do
    case Scoring.latest_score_for_application(app.id) do
      nil ->
        :ok

      %AiScore{scored_at: scored_at} ->
        elapsed = DateTime.diff(DateTime.utc_now(), scored_at, :second)

        if elapsed >= @min_rescore_interval_seconds,
          do: :ok,
          else: {:error, {:too_soon, "wait #{@min_rescore_interval_seconds - elapsed} seconds before re-scoring"}}
    end
  end
end
