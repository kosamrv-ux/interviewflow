defmodule InterviewFlowWeb.AiScoreController do
  use InterviewFlowWeb, :controller

  alias InterviewFlow.Scoring
  alias InterviewFlow.Candidates

  @doc "GET /api/v1/applications/:application_id/scores"
  def index(conn, %{"application_id" => application_id}) do
    company_id = conn.assigns.current_user.company_id

    with {:ok, _application} <- Candidates.get_application(company_id, application_id) do
      scores = Scoring.list_scores(application_id)

      conn
      |> put_status(:ok)
      |> json(Enum.map(scores, &render_score/1))
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{errors: [%{message: "Application not found", code: "not_found"}]})
    end
  end

  @doc "GET /api/v1/scores/:id"
  def show(conn, %{"id" => score_id}) do
    case Scoring.get_score(score_id) do
      {:ok, score} ->
        conn |> put_status(:ok) |> json(render_score_detail(score))

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{errors: [%{message: "Score not found", code: "not_found"}]})
    end
  end

  @doc """
  POST /api/v1/scores/:id/override — Allows a recruiter to override the AI score.
  Creates an audit trail entry and recomputes the application composite score.
  """
  def override(conn, %{"id" => score_id} = params) do
    actor = conn.assigns.current_user

    override_attrs = Map.take(params, ["composite_score", "breakdown", "recommended_action",
                                        "strengths", "areas_for_growth"])

    with {:ok, score} <- Scoring.get_score(score_id),
         {:ok, updated} <- Scoring.override_score(score, override_attrs, actor) do
      conn |> put_status(:ok) |> json(render_score_detail(updated))
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{errors: [%{message: "Score not found", code: "not_found"}]})

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
    end
  end

  defp render_score(score) do
    %{
      id: score.id,
      application_id: score.application_id,
      composite_score: score.composite_score,
      recommended_action: score.recommended_action,
      confidence: score.confidence,
      status: score.status,
      scored_by: score.scored_by,
      model_version: score.model_version,
      inserted_at: score.inserted_at
    }
  end

  defp render_score_detail(score) do
    Map.merge(render_score(score), %{
      breakdown: score.breakdown,
      strengths: score.strengths,
      areas_for_growth: score.areas_for_growth,
      processing_ms: score.processing_ms,
      prompt_version: score.prompt_version
    })
  end

  defp format_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", to_string(v)) end)
    end)
    |> Enum.flat_map(fn {f, msgs} -> Enum.map(msgs, &%{field: to_string(f), message: &1, code: "invalid"}) end)
  end
end
