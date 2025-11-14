defmodule InterviewFlow.JobsTest do
  use InterviewFlow.DataCase, async: true

  alias InterviewFlow.Jobs

  describe "create_job/3" do
    test "creates a job with valid attributes" do
      company = insert(:company)
      user = insert(:user, company: company)

      attrs = %{
        "title" => "Senior Elixir Engineer",
        "department" => "Engineering",
        "location" => "Remote",
        "remote_policy" => "remote",
        "employment_type" => "full_time",
        "description" => "We are looking for an experienced Elixir engineer.",
        "salary_min" => 12_000_000,
        "salary_max" => 18_000_000
      }

      assert {:ok, job} = Jobs.create_job(company.id, user.id, attrs)

      assert job.title == "Senior Elixir Engineer"
      assert job.status == "draft"
      assert job.company_id == company.id
      assert job.created_by_id == user.id
      assert job.pipeline_stages == ["applied", "screen", "interview", "offer", "hired"]
    end

    test "returns error when title is missing" do
      company = insert(:company)
      user = insert(:user, company: company)

      assert {:error, changeset} = Jobs.create_job(company.id, user.id, %{"title" => ""})
      assert %{title: [_]} = errors_on(changeset)
    end

    test "returns error when salary_min >= salary_max" do
      company = insert(:company)
      user = insert(:user, company: company)

      attrs = %{"title" => "Engineer", "salary_min" => 10_000_000, "salary_max" => 5_000_000}
      assert {:error, changeset} = Jobs.create_job(company.id, user.id, attrs)
      assert %{salary_max: [_]} = errors_on(changeset)
    end
  end

  describe "publish_job/1" do
    test "transitions a draft job to open" do
      company = insert(:company)
      user = insert(:user, company: company)
      job = insert(:draft_job, company: company, created_by: user)

      assert {:ok, published} = Jobs.publish_job(job)
      assert published.status == "open"
      assert published.published_at != nil
    end

    test "returns error when job is already open" do
      company = insert(:company)
      user = insert(:user, company: company)
      job = insert(:job, company: company, created_by: user, status: "open")

      assert {:error, :invalid_state_transition} = Jobs.publish_job(job)
    end
  end

  describe "list_jobs/2" do
    test "returns only non-deleted jobs for the company" do
      company = insert(:company)
      user = insert(:user, company: company)
      other_company = insert(:company)

      _job1 = insert(:job, company: company, created_by: user, title: "Job A")
      _job2 = insert(:job, company: company, created_by: user, title: "Job B")
      _other = insert(:job, company: other_company, created_by: insert(:user, company: other_company))
      _deleted = insert(:job, company: company, created_by: user, title: "Deleted Job",
                         deleted_at: DateTime.utc_now() |> DateTime.truncate(:microsecond))

      assert {:ok, result} = Jobs.list_jobs(company.id)
      assert length(result.data) == 2
      titles = Enum.map(result.data, & &1.title)
      assert "Job A" in titles
      assert "Job B" in titles
    end

    test "filters by status" do
      company = insert(:company)
      user = insert(:user, company: company)

      insert(:job, company: company, created_by: user, status: "open")
      insert(:draft_job, company: company, created_by: user)

      assert {:ok, result} = Jobs.list_jobs(company.id, status: "open")
      assert length(result.data) == 1
      assert hd(result.data).status == "open"
    end
  end

  describe "pipeline_stage_counts/1" do
    test "returns counts by pipeline stage" do
      company = insert(:company)
      user = insert(:user, company: company)
      job = insert(:job, company: company, created_by: user)

      candidate1 = insert(:candidate, company: company)
      candidate2 = insert(:candidate, company: company)
      candidate3 = insert(:candidate, company: company)

      insert(:application, job: job, candidate: candidate1, pipeline_stage: "applied")
      insert(:application, job: job, candidate: candidate2, pipeline_stage: "screen")
      insert(:application, job: job, candidate: candidate3, pipeline_stage: "screen")

      counts = Jobs.pipeline_stage_counts(job.id)

      assert counts["applied"] == 1
      assert counts["screen"] == 2
      assert Map.get(counts, "interview") == nil
    end
  end
end
