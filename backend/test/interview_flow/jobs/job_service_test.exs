defmodule InterviewFlow.Jobs.JobServiceTest do
  use InterviewFlow.DataCase, async: true

  alias InterviewFlow.Jobs.JobService
  alias InterviewFlow.Factory

  setup do
    company = Factory.insert(:company)
    admin = Factory.insert(:user, company_id: company.id, role: "admin")
    recruiter = Factory.insert(:user, company_id: company.id, role: "recruiter")
    interviewer = Factory.insert(:user, company_id: company.id, role: "interviewer")

    %{company: company, admin: admin, recruiter: recruiter, interviewer: interviewer}
  end

  describe "publish/2" do
    test "publishes a valid draft job", %{company: company, recruiter: recruiter} do
      job = Factory.insert(:job,
        company_id: company.id,
        status: "draft",
        title: "Elixir Engineer",
        description: "We are hiring.",
        required_skills: ["elixir"]
      )

      assert {:ok, published} = JobService.publish(job, recruiter)
      assert published.status == "published"
      assert published.published_at != nil
    end

    test "admin can publish a job", %{company: company, admin: admin} do
      job = Factory.insert(:job,
        company_id: company.id,
        status: "draft",
        description: "Great role.",
        required_skills: ["elixir"]
      )

      assert {:ok, _} = JobService.publish(job, admin)
    end

    test "interviewer cannot publish a job", %{company: company, interviewer: interviewer} do
      job = Factory.insert(:job, company_id: company.id, status: "draft")
      assert {:error, msg} = JobService.publish(job, interviewer)
      assert msg =~ "only admins"
    end

    test "cannot publish an already-published job", %{recruiter: recruiter, company: company} do
      job = Factory.insert(:job, company_id: company.id, status: "published")
      assert {:error, "job is already published"} = JobService.publish(job, recruiter)
    end

    test "rejects a job without required skills", %{recruiter: recruiter, company: company} do
      job = Factory.insert(:job,
        company_id: company.id,
        status: "draft",
        required_skills: []
      )

      assert {:error, msg} = JobService.publish(job, recruiter)
      assert msg =~ "required skill"
    end
  end

  describe "close/2" do
    test "closes a published job", %{admin: admin, company: company} do
      job = Factory.insert(:job, company_id: company.id, status: "published")
      assert {:ok, closed} = JobService.close(job, admin)
      assert closed.status == "closed"
    end

    test "cannot close a draft job", %{admin: admin, company: company} do
      job = Factory.insert(:job, company_id: company.id, status: "draft")
      assert {:error, msg} = JobService.close(job, admin)
      assert msg =~ "unpublished"
    end

    test "cannot close an already-closed job", %{admin: admin, company: company} do
      job = Factory.insert(:job, company_id: company.id, status: "closed")
      assert {:error, "job is already closed"} = JobService.close(job, admin)
    end
  end

  describe "archive/2" do
    test "archives a closed job and returns final analytics", %{admin: admin, company: company} do
      job = Factory.insert(:job, company_id: company.id, status: "closed")
      assert {:ok, %{job: archived, final_analytics: analytics}} = JobService.archive(job, admin)
      assert archived.status == "archived"
      assert is_map(analytics)
    end

    test "cannot archive a published job", %{admin: admin, company: company} do
      job = Factory.insert(:job, company_id: company.id, status: "published")
      assert {:error, msg} = JobService.archive(job, admin)
      assert msg =~ "closed"
    end
  end

  describe "accepting_applications?/1" do
    test "returns true only for published jobs" do
      assert JobService.accepting_applications?(%{status: "published"})
      refute JobService.accepting_applications?(%{status: "draft"})
      refute JobService.accepting_applications?(%{status: "closed"})
      refute JobService.accepting_applications?(%{status: "archived"})
    end
  end
end
