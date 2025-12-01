defmodule InterviewFlow.CandidatesTest do
  use InterviewFlow.DataCase, async: true

  alias InterviewFlow.Candidates
  alias InterviewFlow.Candidates.{Candidate, Application}

  describe "upsert_candidate/2" do
    test "creates a new candidate with valid attributes" do
      company = insert(:company)

      attrs = %{
        "email" => "alice@example.com",
        "full_name" => "Alice Smith",
        "source" => "linkedin",
        "linkedin_url" => "https://linkedin.com/in/alicesmith"
      }

      assert {:ok, candidate} = Candidates.upsert_candidate(company.id, attrs)
      assert candidate.email == "alice@example.com"
      assert candidate.full_name == "Alice Smith"
      assert candidate.source == "linkedin"
      assert candidate.company_id == company.id
    end

    test "updates existing candidate on email conflict" do
      company = insert(:company)
      existing = insert(:candidate, company: company, email: "bob@example.com", full_name: "Bob Old")

      attrs = %{
        "email" => "bob@example.com",
        "full_name" => "Bob Updated",
        "source" => "referral"
      }

      assert {:ok, updated} = Candidates.upsert_candidate(company.id, attrs)
      assert updated.id == existing.id
      assert updated.full_name == "Bob Updated"
    end

    test "returns error for invalid email" do
      company = insert(:company)
      assert {:error, changeset} = Candidates.upsert_candidate(company.id, %{"email" => "bad", "full_name" => "Test"})
      assert %{email: [_]} = errors_on(changeset)
    end
  end

  describe "Application.advance_changeset/3" do
    test "advances to a valid next stage" do
      company = insert(:company)
      user = insert(:user, company: company)
      job = insert(:job, company: company, created_by: user,
                   pipeline_stages: ["applied", "screen", "interview", "offer", "hired"])
      candidate = insert(:candidate, company: company)
      application = insert(:application, job: job, candidate: candidate, pipeline_stage: "applied")

      changeset = Application.advance_changeset(application, "screen", job)

      assert changeset.valid?
      assert changeset.changes.pipeline_stage == "screen"
    end

    test "returns error when trying to move to a previous stage" do
      company = insert(:company)
      user = insert(:user, company: company)
      job = insert(:job, company: company, created_by: user,
                   pipeline_stages: ["applied", "screen", "interview"])
      candidate = insert(:candidate, company: company)
      application = insert(:application, job: job, candidate: candidate, pipeline_stage: "screen")

      changeset = Application.advance_changeset(application, "applied", job)

      refute changeset.valid?
      assert %{pipeline_stage: [_]} = errors_on(changeset)
    end

    test "returns error for invalid stage name" do
      company = insert(:company)
      user = insert(:user, company: company)
      job = insert(:job, company: company, created_by: user)
      candidate = insert(:candidate, company: company)
      application = insert(:application, job: job, candidate: candidate)

      changeset = Application.advance_changeset(application, "nonexistent_stage", job)

      refute changeset.valid?
    end

    test "returns error when application is not active" do
      company = insert(:company)
      user = insert(:user, company: company)
      job = insert(:job, company: company, created_by: user)
      candidate = insert(:candidate, company: company)
      application = insert(:application, job: job, candidate: candidate,
                            status: "rejected", pipeline_stage: "applied")

      changeset = Application.advance_changeset(application, "screen", job)

      refute changeset.valid?
      assert %{status: [_]} = errors_on(changeset)
    end
  end

  describe "list_candidates/2" do
    test "returns only candidates for the given company" do
      company_a = insert(:company)
      company_b = insert(:company)

      insert(:candidate, company: company_a, full_name: "Alice A")
      insert(:candidate, company: company_a, full_name: "Bob A")
      insert(:candidate, company: company_b, full_name: "Carol B")

      {:ok, result} = Candidates.list_candidates(company_a.id)
      assert length(result.data) == 2
      names = Enum.map(result.data, & &1.full_name)
      assert "Alice A" in names
      assert "Bob A" in names
      refute "Carol B" in names
    end
  end
end
