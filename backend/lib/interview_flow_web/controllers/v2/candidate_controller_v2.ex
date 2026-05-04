defmodule InterviewFlowWeb.V2.CandidateControllerV2 do
  @moduledoc """
  V2 candidate endpoints with improved response schema.

  V2 changes:
  - `score` field renamed to `composite_score` for clarity
  - New `timeline` endpoint returns chronological activity log
  - Candidate list supports full-text search via `q` param
  - Resume URL is a pre-signed GCS link (1hr expiry) instead of raw path
  """

  use InterviewFlowWeb, :controller

  alias InterviewFlow.Candidates
  alias InterviewFlow.Scoring

  action_fallback InterviewFlowWeb.V2.FallbackControllerV2

  def index(conn, params) do
    org_id = conn.assigns.org_id
    page = String.to_integer(params["page"] || "1")
    per_page = min(String.to_integer(params["per_page"] || "20"), 100)
    q = params["q"]

    %{entries: candidates, total: total} =
      Candidates.list_for_org(org_id, %{q: q, job_id: params["job_id"]},
        page: page,
        per_page: per_page
      )

    json(conn, %{
      data: Enum.map(candidates, &format_candidate/1),
      meta: %{total: total, page: page, per_page: per_page, total_pages: ceil(total / per_page)}
    })
  end

  def show(conn, %{"id" => id}) do
    with {:ok, candidate} <- Candidates.get_for_org(conn.assigns.org_id, id) do
      json(conn, %{data: format_candidate(candidate)})
    end
  end

  def create(conn, %{"candidate" => params}) do
    org_id = conn.assigns.org_id

    with {:ok, candidate} <- Candidates.create(Map.put(params, "org_id", org_id)) do
      conn |> put_status(:created) |> json(%{data: format_candidate(candidate)})
    end
  end

  def update(conn, %{"id" => id, "candidate" => params}) do
    with {:ok, candidate} <- Candidates.get_for_org(conn.assigns.org_id, id),
         {:ok, updated} <- Candidates.update(candidate, params) do
      json(conn, %{data: format_candidate(updated)})
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, candidate} <- Candidates.get_for_org(conn.assigns.org_id, id),
         {:ok, _} <- Candidates.delete(candidate) do
      send_resp(conn, :no_content, "")
    end
  end

  def score(conn, %{"id" => id}) do
    with {:ok, candidate} <- Candidates.get_for_org(conn.assigns.org_id, id),
         {:ok, score_data} <- Scoring.get_candidate_score(candidate) do
      json(conn, %{
        data: %{
          candidate_id: candidate.id,
          composite_score: score_data.composite,
          dimensions: score_data.dimensions,
          rubric_version: score_data.rubric_version,
          scored_at: DateTime.to_iso8601(score_data.scored_at)
        }
      })
    end
  end

  def timeline(conn, %{"id" => id}) do
    with {:ok, candidate} <- Candidates.get_for_org(conn.assigns.org_id, id) do
      events = Candidates.get_timeline(candidate)
      json(conn, %{data: events})
    end
  end

  defp format_candidate(c) do
    %{
      id: c.id,
      name: c.name,
      email: c.email,
      phone: c.phone,
      location: c.location,
      composite_score: c.score,
      resume_url: c.resume_gcs_key && signed_resume_url(c.resume_gcs_key),
      status: c.status,
      org_id: c.org_id,
      inserted_at: format_dt(c.inserted_at),
      updated_at: format_dt(c.updated_at)
    }
  end

  defp format_dt(nil), do: nil
  defp format_dt(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_dt(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt) <> "Z"

  defp signed_resume_url(key) do
    case InterviewFlow.GCS.signed_url(key, expires_in: 3600) do
      {:ok, url} -> url
      _ -> nil
    end
  end
end
