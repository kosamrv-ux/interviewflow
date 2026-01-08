defmodule InterviewFlow.Candidates.Pipeline do
  @moduledoc """
  State machine for the candidate application pipeline.

  Tracks progression from initial application through to hire or rejection.
  Each transition has business rules that must be satisfied before the move
  is allowed (e.g., a completed AI score before advancing to the offer stage).

  ## Stage Order

    applied → screening → phone_screen → technical → onsite → offer → hired
                                                                      ↘ rejected (any stage)

  """

  alias InterviewFlow.Repo
  alias InterviewFlow.Candidates.Application
  alias InterviewFlow.Scoring

  @ordered_stages ~w(applied screening phone_screen technical onsite offer hired)

  @doc "Returns all valid pipeline stages in order."
  def stages, do: @ordered_stages

  @doc """
  Returns the next stage after the current one, or nil if already at the end.
  """
  def next_stage(current) do
    idx = Enum.find_index(@ordered_stages, &(&1 == current))
    if idx && idx < length(@ordered_stages) - 1, do: Enum.at(@ordered_stages, idx + 1), else: nil
  end

  @doc """
  Advances an application to the next pipeline stage.

  Validates business rules:
  - Cannot advance a rejected or hired application
  - Cannot skip stages
  - Requires at least one AI score before moving past phone_screen
  """
  @spec advance(Application.t()) :: {:ok, Application.t()} | {:error, String.t()}
  def advance(%Application{stage: "rejected"} = _app),
    do: {:error, "cannot advance a rejected application"}

  def advance(%Application{stage: "hired"} = _app),
    do: {:error, "application has already been hired"}

  def advance(%Application{} = app) do
    with :ok <- check_scoring_prerequisite(app),
         next when not is_nil(next) <- next_stage(app.stage) do
      app
      |> Application.stage_changeset(%{stage: next})
      |> Repo.update()
    else
      nil -> {:error, "application is already at the final stage"}
      err -> err
    end
  end

  @doc "Moves an application to the rejected stage from any active stage."
  @spec reject(Application.t(), String.t() | nil) :: {:ok, Application.t()} | {:error, any()}
  def reject(%Application{stage: "hired"} = _app),
    do: {:error, "cannot reject a hired candidate"}

  def reject(%Application{} = app, reason \\ nil) do
    attrs = %{stage: "rejected", rejection_reason: reason}

    app
    |> Application.stage_changeset(attrs)
    |> Repo.update()
  end

  @doc "Marks an application as hired (final positive outcome)."
  @spec hire(Application.t()) :: {:ok, Application.t()} | {:error, any()}
  def hire(%Application{stage: "offer"} = app) do
    app
    |> Application.stage_changeset(%{stage: "hired", hired_at: DateTime.utc_now()})
    |> Repo.update()
  end

  def hire(%Application{stage: stage}),
    do: {:error, "can only hire from offer stage, current stage is #{stage}"}

  @doc "Returns a map of stage => count for all applications under a job."
  @spec pipeline_counts(Ecto.UUID.t()) :: %{String.t() => non_neg_integer()}
  def pipeline_counts(job_id) do
    import Ecto.Query

    counts =
      from(a in Application,
        where: a.job_id == ^job_id,
        group_by: a.stage,
        select: {a.stage, count(a.id)}
      )
      |> Repo.all()
      |> Map.new()

    Enum.reduce(@ordered_stages ++ ["rejected"], %{}, fn stage, acc ->
      Map.put(acc, stage, Map.get(counts, stage, 0))
    end)
  end

  # ── Private helpers ──────────────────────────────────────────────────────

  # Require at least one completed AI score before advancing beyond phone_screen
  defp check_scoring_prerequisite(%Application{stage: "phone_screen", id: id}) do
    if Scoring.has_score?(id),
      do: :ok,
      else: {:error, "an AI score is required before advancing past phone screen"}
  end

  defp check_scoring_prerequisite(_), do: :ok
end
