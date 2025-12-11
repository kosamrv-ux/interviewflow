defmodule InterviewFlowWeb.AiScoreControllerTest do
  use InterviewFlowWeb.ConnCase, async: true

  alias InterviewFlow.Scoring

  describe "GET /api/v1/applications/:application_id/scores" do
    test "returns scores for an application the user has access to", %{conn: conn} do
      company = insert(:company)
      user = insert(:user, company: company, role: "recruiter")
      job = insert(:job, company: company, created_by: user)
      candidate = insert(:candidate, company: company)
      application = insert(:application, job: job, candidate: candidate)
      session = insert(:video_session, application: application)

      insert(:ai_score,
        application: application,
        video_session: session,
        composite_score: Decimal.new("8.2"),
        recommended_action: "advance"
      )

      conn = authenticate(conn, user)
      response = conn |> get("/api/v1/applications/#{application.id}/scores") |> json_response(200)

      assert length(response["data"]) == 1
      [score] = response["data"]
      assert score["composite_score"] == "8.2"
      assert score["recommended_action"] == "advance"
    end

    test "returns 404 for an application in a different company", %{conn: conn} do
      company_a = insert(:company)
      company_b = insert(:company)
      user = insert(:user, company: company_a, role: "recruiter")
      job = insert(:job, company: company_b, created_by: insert(:user, company: company_b))
      candidate = insert(:candidate, company: company_b)
      application = insert(:application, job: job, candidate: candidate)

      conn = authenticate(conn, user)
      conn |> get("/api/v1/applications/#{application.id}/scores") |> json_response(404)
    end

    test "returns empty list when no scores exist yet", %{conn: conn} do
      company = insert(:company)
      user = insert(:user, company: company, role: "recruiter")
      job = insert(:job, company: company, created_by: user)
      candidate = insert(:candidate, company: company)
      application = insert(:application, job: job, candidate: candidate)

      conn = authenticate(conn, user)
      response = conn |> get("/api/v1/applications/#{application.id}/scores") |> json_response(200)

      assert response["data"] == []
    end

    test "requires authentication", %{conn: conn} do
      conn |> get("/api/v1/applications/some-id/scores") |> json_response(401)
    end
  end

  describe "GET /api/v1/scores/:id" do
    test "returns the score detail with breakdown", %{conn: conn} do
      company = insert(:company)
      user = insert(:user, company: company, role: "recruiter")
      job = insert(:job, company: company, created_by: user)
      candidate = insert(:candidate, company: company)
      application = insert(:application, job: job, candidate: candidate)
      session = insert(:video_session, application: application)

      score = insert(:ai_score,
        application: application,
        video_session: session,
        breakdown: %{
          "technical_depth" => %{"score" => 8.0, "rationale" => "Solid", "weight" => 0.35},
          "communication" => %{"score" => 7.5, "rationale" => "Good", "weight" => 0.25},
          "problem_solving" => %{"score" => 9.0, "rationale" => "Excellent", "weight" => 0.20},
          "culture_fit" => %{"score" => 8.0, "rationale" => "Great", "weight" => 0.10},
          "coding_quality" => %{"score" => 7.0, "rationale" => "OK", "weight" => 0.10}
        }
      )

      conn = authenticate(conn, user)
      response = conn |> get("/api/v1/scores/#{score.id}") |> json_response(200)

      assert response["id"] == score.id
      assert Map.has_key?(response, "breakdown")
      assert Map.has_key?(response["breakdown"], "technical_depth")
    end

    test "returns 404 for a score not belonging to user's company", %{conn: conn} do
      company_a = insert(:company)
      company_b = insert(:company)
      user = insert(:user, company: company_a, role: "recruiter")

      other_job = insert(:job, company: company_b, created_by: insert(:user, company: company_b))
      other_candidate = insert(:candidate, company: company_b)
      other_app = insert(:application, job: other_job, candidate: other_candidate)
      other_session = insert(:video_session, application: other_app)
      other_score = insert(:ai_score, application: other_app, video_session: other_session)

      conn = authenticate(conn, user)
      conn |> get("/api/v1/scores/#{other_score.id}") |> json_response(404)
    end
  end

  describe "POST /api/v1/scores/:id/override" do
    test "allows recruiter to override recommended_action", %{conn: conn} do
      company = insert(:company)
      user = insert(:user, company: company, role: "recruiter")
      job = insert(:job, company: company, created_by: user)
      candidate = insert(:candidate, company: company)
      application = insert(:application, job: job, candidate: candidate)
      session = insert(:video_session, application: application)

      score = insert(:ai_score,
        application: application,
        video_session: session,
        recommended_action: "hold"
      )

      conn = authenticate(conn, user)

      body = %{
        "composite_score" => "8.5",
        "recommended_action" => "advance",
        "breakdown" => score.breakdown
      }

      response = conn |> post("/api/v1/scores/#{score.id}/override", body) |> json_response(200)

      assert response["recommended_action"] == "advance"
      assert response["composite_score"] == "8.5"
    end
  end

  defp authenticate(conn, user) do
    {:ok, %{access_token: token}} = InterviewFlow.Auth.Guardian.issue_token_pair(user)

    conn
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("content-type", "application/json")
  end
end
