defmodule InterviewFlowWeb.AnalyticsController do
  @moduledoc """
  Endpoints for hiring funnel analytics and recruiter dashboard data.
  All routes require authentication. Aggregate endpoints are accessible
  to all roles; job-level detail requires recruiter or admin.
  """

  use InterviewFlowWeb, :controller

  alias InterviewFlow.Jobs.{JobAnalytics, Matcher}
  alias InterviewFlow.Scoring.Ranking
  alias InterviewFlow.{Jobs, Candidates}

  action_fallback InterviewFlowWeb.FallbackController

  @doc "GET /api/v1/analytics/summary — company-wide KPIs"
  def summary(conn, _params) do
    company_id = conn.assigns.current_user.company_id
    data = JobAnalytics.company_summary(company_id)
    render(conn, :summary, data: data)
  end

  @doc "GET /api/v1/analytics/jobs/:job_id/funnel"
  def funnel(conn, %{"job_id" => job_id}) do
    company_id = conn.assigns.current_user.company_id

    with {:ok, _job} <- Jobs.get_job(company_id, job_id) do
      data = JobAnalytics.funnel(job_id)
      render(conn, :funnel, data: data)
    end
  end

  @doc "GET /api/v1/analytics/jobs/:job_id/time_in_stage"
  def time_in_stage(conn, %{"job_id" => job_id}) do
    company_id = conn.assigns.current_user.company_id

    with {:ok, _job} <- Jobs.get_job(company_id, job_id) do
      data = JobAnalytics.avg_time_in_stage(job_id)
      render(conn, :time_in_stage, data: data)
    end
  end

  @doc "GET /api/v1/analytics/jobs/:job_id/sources"
  def sources(conn, %{"job_id" => job_id}) do
    company_id = conn.assigns.current_user.company_id

    with {:ok, _job} <- Jobs.get_job(company_id, job_id) do
      data = JobAnalytics.source_breakdown(job_id)
      render(conn, :sources, data: data)
    end
  end

  @doc "GET /api/v1/analytics/jobs/:job_id/rankings"
  def rankings(conn, %{"job_id" => job_id}) do
    company_id = conn.assigns.current_user.company_id

    with {:ok, _job} <- Jobs.get_job(company_id, job_id) do
      data = Ranking.ranked_list(job_id)
      render(conn, :rankings, data: data)
    end
  end

  @doc "GET /api/v1/analytics/jobs/:job_id/match?candidate_id=:id"
  def match(conn, %{"job_id" => job_id, "candidate_id" => candidate_id}) do
    company_id = conn.assigns.current_user.company_id

    with {:ok, job} <- Jobs.get_job(company_id, job_id),
         {:ok, candidate} <- Candidates.get_candidate(company_id, candidate_id) do
      result = Matcher.match(candidate, job)
      render(conn, :match, data: result)
    end
  end
end
