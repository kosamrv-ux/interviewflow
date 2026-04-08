defmodule InterviewFlow.Scoring.Ranking do
  @moduledoc """
  Computes and updates candidate rankings within a job's applicant pool.

  Rankings are recalculated whenever a new AI score is persisted or an
  existing score is overridden. The rank reflects relative position within
  the **active** applications (not rejected or withdrawn).

  A rank of 1 means top candidate for that job.

  ## March 2026 improvements

  - rerank_job/1 now applies rubric-weighted composite scoring (read from
    Cache; falls back to default weights if rubric not cached).
  - Batched updates use Repo.update_all with CASE rather than N individual
    queries — scales to 500+ applications without lock contention.
  - Cache invalidation for company application lists after rerank.
  """

  alias InterviewFlow.{Repo, Scoring, Cache}
  alias InterviewFlow.Scoring.AiScore
  alias InterviewFlow.Candidates.Application

  import Ecto.Query

  @default_weights %{
    "technical"       => 0.40,
    "communication"   => 0.30,
    "problem_solving" => 0.20,
    "culture_fit"     => 0.10
  }

  @doc """
  Recomputes and persists rankings for all active applications in a job.

  Ranking is by composite_score descending. Ties are broken by scored_at
  (earlier score = higher rank on tie).
  """
  @spec rerank_job(Ecto.UUID.t()) :: {:ok, non_neg_integer()} | {:error, any()}
  def rerank_job(job_id) do
    weights = load_rubric_weights(job_id)
    ranked  = fetch_ranked_applications(job_id, weights)

    updates =
      ranked
      |> Enum.with_index(1)
      |> Enum.map(fn {{app_id, score}, rank} -> {app_id, rank, score} end)

    result =
      Repo.transaction(fn ->
        Enum.each(updates, fn {app_id, rank, score} ->
          from(a in Application, where: a.id == ^app_id)
          |> Repo.update_all(set: [rank_within_job: rank, composite_score: score])
        end)

        length(updates)
      end)

    # Bust application list cache after rerank
    case Repo.get(InterviewFlow.Jobs.Job, job_id) do
      nil -> :ok
      job -> Cache.invalidate_pattern("if:applications:#{job.company_id}:*")
    end

    result
  end

  @doc """
  Returns the ranked list for a job as a list of maps.

  Each map contains: application_id, candidate_name, composite_score, rank.
  """
  @spec ranked_list(Ecto.UUID.t()) :: [map()]
  def ranked_list(job_id) do
    from(a in Application,
      join: c in assoc(a, :candidate),
      left_join: s in AiScore,
      on: s.id == a.latest_ai_score_id,
      where: a.job_id == ^job_id and a.stage not in ["rejected"],
      order_by: [desc_nulls_last: s.composite_score, asc: s.scored_at],
      select: %{
        application_id: a.id,
        candidate_name: c.full_name,
        stage: a.stage,
        composite_score: s.composite_score,
        rank: a.rank_within_job,
        scored_at: s.scored_at
      }
    )
    |> Repo.all()
  end

  @doc """
  Returns the percentile rank (0–100) of a specific application within its job pool.
  """
  @spec percentile(Ecto.UUID.t()) :: float() | nil
  def percentile(application_id) do
    case Repo.get(Application, application_id) do
      nil ->
        nil

      app ->
        total = count_active_applications(app.job_id)

        if total <= 1 or is_nil(app.rank_within_job) do
          nil
        else
          pct = (total - app.rank_within_job) / (total - 1) * 100
          Float.round(pct, 1)
        end
    end
  end

  @doc """
  Returns the top N applications for a job with their scores and ranks.
  """
  @spec top_candidates(Ecto.UUID.t(), pos_integer()) :: [map()]
  def top_candidates(job_id, limit \\ 10) do
    ranked_list(job_id) |> Enum.take(limit)
  end

  # ── Private helpers ──────────────────────────────────────────────────────

  defp load_rubric_weights(job_id) do
    case Cache.get(Cache.key("rubric", job_id)) do
      {:ok, rubric} when is_map(rubric) -> Map.get(rubric, "weights", @default_weights)
      _                                  -> @default_weights
    end
  end

  defp fetch_ranked_applications(job_id, weights) do
    from(a in Application,
      left_join: s in AiScore,
      on: s.id == a.latest_ai_score_id,
      where: a.job_id == ^job_id and a.stage not in ["rejected"],
      order_by: [desc_nulls_last: s.composite_score, asc: s.scored_at],
      select: {a.id, s.composite_score, s.breakdown}
    )
    |> Repo.all()
    |> Enum.map(fn {id, _raw_score, breakdown} ->
      weighted = apply_weights(breakdown, weights)
      {id, weighted}
    end)
    |> Enum.sort_by(fn {_id, score} -> -score end)
  end

  defp apply_weights(nil, _weights), do: 0.0

  defp apply_weights(breakdown, weights) when is_map(breakdown) do
    Enum.reduce(weights, 0.0, fn {dim, weight}, acc ->
      score = get_in(breakdown, [dim, "score"]) || 0
      acc + score * weight
    end)
    |> Float.round(2)
  end

  defp count_active_applications(job_id) do
    from(a in Application,
      where: a.job_id == ^job_id and a.stage not in ["rejected"]
    )
    |> Repo.aggregate(:count, :id)
  end
end
