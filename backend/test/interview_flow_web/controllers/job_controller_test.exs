defmodule InterviewFlowWeb.JobControllerTest do
  use InterviewFlowWeb.ConnCase, async: true

  describe "GET /api/v1/jobs" do
    test "returns paginated jobs for the user's company", %{conn: conn} do
      company = insert(:company)
      user = insert(:user, company: company, role: "recruiter")

      insert(:job, company: company, created_by: user, title: "Backend Engineer", status: "open")
      insert(:job, company: company, created_by: user, title: "Frontend Engineer", status: "open")

      # Job in another company — should NOT appear
      other_company = insert(:company)
      other_user = insert(:user, company: other_company)
      insert(:job, company: other_company, created_by: other_user, title: "Hidden Job", status: "open")

      conn = authenticate(conn, user)
      response = conn |> get("/api/v1/jobs") |> json_response(200)

      titles = Enum.map(response["data"], & &1["title"])
      assert "Backend Engineer" in titles
      assert "Frontend Engineer" in titles
      refute "Hidden Job" in titles
    end

    test "filters by status=draft", %{conn: conn} do
      company = insert(:company)
      user = insert(:user, company: company, role: "recruiter")

      insert(:job, company: company, created_by: user, title: "Open Job", status: "open")
      insert(:job, company: company, created_by: user, title: "Draft Job", status: "draft")

      conn = authenticate(conn, user)
      response = conn |> get("/api/v1/jobs?status=draft") |> json_response(200)

      titles = Enum.map(response["data"], & &1["title"])
      assert "Draft Job" in titles
      refute "Open Job" in titles
    end

    test "requires authentication", %{conn: conn} do
      conn |> get("/api/v1/jobs") |> json_response(401)
    end
  end

  describe "GET /api/v1/jobs/:id" do
    test "returns job details", %{conn: conn} do
      company = insert(:company)
      user = insert(:user, company: company, role: "recruiter")
      job = insert(:job, company: company, created_by: user, title: "Staff Engineer")

      conn = authenticate(conn, user)
      response = conn |> get("/api/v1/jobs/#{job.id}") |> json_response(200)

      assert response["title"] == "Staff Engineer"
      assert response["id"] == job.id
    end

    test "returns 404 for a job in another company", %{conn: conn} do
      company_a = insert(:company)
      company_b = insert(:company)
      user_a = insert(:user, company: company_a, role: "recruiter")
      user_b = insert(:user, company: company_b)
      job_b = insert(:job, company: company_b, created_by: user_b)

      conn = authenticate(conn, user_a)
      conn |> get("/api/v1/jobs/#{job_b.id}") |> json_response(404)
    end
  end

  describe "POST /api/v1/jobs" do
    test "creates a job with valid attributes", %{conn: conn} do
      company = insert(:company)
      user = insert(:user, company: company, role: "recruiter")

      attrs = %{
        title: "Principal Engineer",
        description: "Leading the platform team.",
        department: "Engineering",
        location: "Remote",
        employment_type: "full_time",
        salary_min: 180_000,
        salary_max: 240_000,
        pipeline_stages: ["applied", "screen", "interview", "offer", "hired"]
      }

      conn = authenticate(conn, user)
      response = conn |> post("/api/v1/jobs", attrs) |> json_response(201)

      assert response["title"] == "Principal Engineer"
      assert response["status"] == "draft"
    end

    test "returns 422 when salary_min > salary_max", %{conn: conn} do
      company = insert(:company)
      user = insert(:user, company: company, role: "recruiter")

      attrs = %{
        title: "Invalid Salary Job",
        description: "Test",
        employment_type: "full_time",
        salary_min: 300_000,
        salary_max: 100_000
      }

      conn = authenticate(conn, user)
      response = conn |> post("/api/v1/jobs", attrs) |> json_response(422)
      assert Map.has_key?(response, "errors")
    end

    test "returns 422 when pipeline_stages doesn't start with applied", %{conn: conn} do
      company = insert(:company)
      user = insert(:user, company: company, role: "recruiter")

      attrs = %{
        title: "Bad Pipeline Job",
        description: "Test",
        employment_type: "full_time",
        pipeline_stages: ["screen", "interview"]
      }

      conn = authenticate(conn, user)
      response = conn |> post("/api/v1/jobs", attrs) |> json_response(422)
      assert Map.has_key?(response, "errors")
    end
  end

  describe "PATCH /api/v1/jobs/:id/publish" do
    test "publishes a draft job", %{conn: conn} do
      company = insert(:company)
      user = insert(:user, company: company, role: "recruiter")
      job = insert(:job, company: company, created_by: user, status: "draft")

      conn = authenticate(conn, user)
      response = conn |> patch("/api/v1/jobs/#{job.id}/publish") |> json_response(200)

      assert response["status"] == "open"
    end
  end

  describe "DELETE /api/v1/jobs/:id" do
    test "archives a job (admin only)", %{conn: conn} do
      company = insert(:company)
      admin = insert(:user, company: company, role: "admin")
      job = insert(:job, company: company, created_by: admin, status: "open")

      conn = authenticate(conn, admin)
      conn |> delete("/api/v1/jobs/#{job.id}") |> json_response(204)
    end

    test "returns 403 for recruiter", %{conn: conn} do
      company = insert(:company)
      admin = insert(:user, company: company, role: "admin")
      recruiter = insert(:user, company: company, role: "recruiter")
      job = insert(:job, company: company, created_by: admin)

      conn = authenticate(conn, recruiter)
      conn |> delete("/api/v1/jobs/#{job.id}") |> json_response(403)
    end
  end

  defp authenticate(conn, user) do
    {:ok, %{access_token: token}} = InterviewFlow.Auth.Guardian.issue_token_pair(user)

    conn
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("content-type", "application/json")
  end
end
