defmodule InterviewFlow.Scoring do
  @moduledoc """
  The Scoring context manages AI score ingestion, retrieval,
  and composite score recomputation for applications.
  """

  import Ecto.Query, warn: false
  alias InterviewFlow.Repo
  alias InterviewFlow.Scoring.AiScore
  alias InterviewFlow.Candidates.Application

  @doc "Lists all scores for an application, most recent first."
  def list_scores(application_id) do
    AiScore
    |> where([s], s.application_id == ^application_id)
    |> order_by([s], [desc: s.inserted_at])
    |> Repo.all()
  end

  @doc "Returns a score by ID."
  def get_score(score_id) do
    case Repo.get(AiScore, score_id) do
      nil -> {:error, :not_found}
      score -> {:ok, score}
    end
  end

  @doc """
  Inserts or updates a score for a given (application_id, video_session_id) pair.
  After persisting, triggers composite score recomputation on the application.
  """
  def upsert_score(attrs) do
    Repo.transact(fn ->
      with {:ok, score} <-
             %AiScore{}
             |> AiScore.changeset(attrs)
             |> Repo.insert(
               on_conflict: {:replace_all_except, [:id, :application_id, :video_session_id, :inserted_at]},
               conflict_target: [:application_id, :video_session_id],
               returning: true
             ),
           {:ok, _application} <- recompute_composite_score(attrs.application_id) do
        {:ok, score}
      end
    end)
  end

  @doc """
  Allows a recruiter to override an AI score with their own assessment.
  The override is audited and the composite score recomputed.
  """
  def override_score(score, override_attrs, actor) do
    Repo.transact(fn ->
      with {:ok, updated} <-
             score
             |> AiScore.override_changeset(override_attrs, actor.id)
             |> Repo.update(),
           {:ok, _application} <- recompute_composite_score(score.application_id) do
        {:ok, updated}
      end
    end)
  end

  @doc """
  Recomputes the composite score on an application as the weighted average
  of all non-failed AI scores (most recent per session wins).
  """
  def recompute_composite_score(application_id) do
    scores =
      AiScore
      |> where([s], s.application_id == ^application_id and s.status in ["completed", "overridden"])
      |> order_by([s], [desc: s.inserted_at])
      |> Repo.all()

    if scores == [] do
      {:ok, nil}
    else
      # Weight more recent scores higher (simple decay — latest score has 2x weight)
      {total_weight, weighted_sum} =
        scores
        |> Enum.with_index()
        |> Enum.reduce({0, Decimal.new("0")}, fn {{score, idx}, _}, {tw, ws} ->
          weight = if idx == 0, do: Decimal.new("2"), else: Decimal.new("1")
          {tw + Decimal.to_float(weight), Decimal.add(ws, Decimal.mult(score.composite_score, weight))}
        end)

      composite =
        weighted_sum
        |> Decimal.div(Decimal.from_float(total_weight))
        |> Decimal.round(2)

      Application
      |> where([a], a.id == ^application_id)
      |> Repo.update_all(set: [composite_score: composite, updated_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)])

      # Also recompute rank within job
      recompute_job_rankings(application_id)
    end
  end

  defp recompute_job_rankings(application_id) do
    case Repo.get(Application, application_id) do
      nil ->
        {:ok, nil}

      application ->
        # Rank all active applications for this job by composite score descending
        Application
        |> where([a], a.job_id == ^application.job_id and a.status == "active" and not is_nil(a.composite_score))
        |> order_by([a], [desc: a.composite_score])
        |> Repo.all()
        |> Enum.with_index(1)
        |> Enum.each(fn {app, rank} ->
          Repo.update_all(
            from(a in Application, where: a.id == ^app.id),
            set: [rank_within_job: rank]
          )
        end)

        {:ok, application}
    end
  end
end
