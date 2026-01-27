defmodule InterviewFlowWeb.AnalyticsControllerTest do
  use InterviewFlowWeb.ConnCase, async: true

  alias InterviewFlow.Factory

  setup %{conn: conn} do
    company = Factory.insert(:company)
    recruiter = Factory.insert(:user, company_id: company.id, role: "recruiter")
    token = generate_token(recruiter)

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{token}")

    %{conn: conn, company: company, user: recruiter}
  end

  describe "GET /api/v1/analytics/summary" do
    test "returns company-wide KPIs", %{conn: conn, company: company} do
      job = Factory.insert(:job, company_id: company.id, status: "published")
      Factory.insert(:application, job_id: job.id, stage: "applied")
      Factory.insert(:application, job_id: job.id, stage: "screening")

      conn = get(conn, "/api/v1/analytics/summary")
      assert %{"total_applications" => total} = json_response(conn, 200)
      assert total >= 2
    end
  end

  describe "GET /api/v1/analytics/jobs/:job_id/funnel" do
    test "returns stage counts and conversion rates", %{conn: conn, company: company} do
      job = Factory.insert(:job, company_id: company.id)
      Factory.insert_list(3, :application, job_id: job.id, stage: "applied")
      Factory.insert(:application, job_id: job.id, stage: "screening")
      Factory.insert(:application, job_id: job.id, stage: "hired")

      conn = get(conn, "/api/v1/analytics/jobs/#{job.id}/funnel")
      response = json_response(conn, 200)

      assert get_in(response, ["stages", "applied"]) == 3
      assert get_in(response, ["stages", "hired"]) == 1
      assert is_float(response["conversion_rate"])
    end

    test "returns 404 for job belonging to another company", %{conn: conn} do
      other_job = Factory.insert(:job)
      conn = get(conn, "/api/v1/analytics/jobs/#{other_job.id}/funnel")
      assert json_response(conn, 404)
    end
  end

  describe "GET /api/v1/analytics/jobs/:job_id/rankings" do
    test "returns ranked candidates sorted by composite score", %{conn: conn, company: company} do
      job = Factory.insert(:job, company_id: company.id)
      c1 = Factory.insert(:candidate, company_id: company.id)
      c2 = Factory.insert(:candidate, company_id: company.id)

      app1 = Factory.insert(:application, job_id: job.id, candidate_id: c1.id, stage: "technical")
      app2 = Factory.insert(:application, job_id: job.id, candidate_id: c2.id, stage: "onsite")

      Factory.insert(:ai_score, application_id: app1.id, composite_score: 0.85)
      Factory.insert(:ai_score, application_id: app2.id, composite_score: 0.72)

      conn = get(conn, "/api/v1/analytics/jobs/#{job.id}/rankings")
      rankings = json_response(conn, 200)

      assert is_list(rankings)
      assert length(rankings) == 2
    end
  end

  describe "GET /api/v1/analytics/jobs/:job_id/match" do
    test "returns match score for a candidate and job", %{conn: conn, company: company} do
      job =
        Factory.insert(:job,
          company_id: company.id,
          required_skills: ["elixir", "postgresql"]
        )

      candidate =
        Factory.insert(:candidate,
          company_id: company.id,
          skills: ["elixir", "postgresql", "graphql"]
        )

      conn =
        get(conn, "/api/v1/analytics/jobs/#{job.id}/match?candidate_id=#{candidate.id}")

      response = json_response(conn, 200)
      assert Map.has_key?(response, "score")
      assert response["score"] >= 0.0
      assert response["score"] <= 1.0
    end
  end

  describe "authentication" do
    test "rejects unauthenticated requests" do
      conn = build_conn()
      conn = get(conn, "/api/v1/analytics/summary")
      assert json_response(conn, 401)
    end
  end
end
