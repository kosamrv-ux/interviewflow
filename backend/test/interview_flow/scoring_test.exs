defmodule InterviewFlow.ScoringTest do
  use InterviewFlow.DataCase, async: true

  alias InterviewFlow.Scoring
  alias InterviewFlow.Scoring.AiScore

  describe "upsert_score/1" do
    test "inserts a new score with valid attributes" do
      company = insert(:company)
      user = insert(:user, company: company)
      job = insert(:job, company: company, created_by: user)
      candidate = insert(:candidate, company: company)
      application = insert(:application, job: job, candidate: candidate)
      session = insert(:video_session, application: application)

      attrs = %{
        application_id: application.id,
        video_session_id: session.id,
        composite_score: Decimal.new("7.4"),
        recommended_action: "advance",
        overall_rationale: "Candidate demonstrated solid fundamentals with clear communication.",
        scored_by: "gemini-1.5-pro",
        breakdown: %{
          "technical_depth" => %{"score" => 7.5, "rationale" => "Good", "weight" => 0.35},
          "communication" => %{"score" => 8.0, "rationale" => "Excellent", "weight" => 0.25},
          "problem_solving" => %{"score" => 7.0, "rationale" => "Adequate", "weight" => 0.20},
          "culture_fit" => %{"score" => 7.5, "rationale" => "Good fit", "weight" => 0.10},
          "coding_quality" => %{"score" => 6.5, "rationale" => "Needs improvement", "weight" => 0.10}
        }
      }

      assert {:ok, score} = Scoring.upsert_score(attrs)
      assert score.application_id == application.id
      assert score.composite_score == Decimal.new("7.4")
      assert score.recommended_action == "advance"
    end

    test "updates existing score on conflict (application_id, video_session_id)" do
      company = insert(:company)
      user = insert(:user, company: company)
      job = insert(:job, company: company, created_by: user)
      candidate = insert(:candidate, company: company)
      application = insert(:application, job: job, candidate: candidate)
      session = insert(:video_session, application: application)

      base_attrs = %{
        application_id: application.id,
        video_session_id: session.id,
        composite_score: Decimal.new("6.0"),
        recommended_action: "hold",
        overall_rationale: "Initial score.",
        scored_by: "gemini-1.5-pro",
        breakdown: %{
          "technical_depth" => %{"score" => 6.0, "rationale" => "OK", "weight" => 0.35},
          "communication" => %{"score" => 6.0, "rationale" => "OK", "weight" => 0.25},
          "problem_solving" => %{"score" => 6.0, "rationale" => "OK", "weight" => 0.20},
          "culture_fit" => %{"score" => 6.0, "rationale" => "OK", "weight" => 0.10},
          "coding_quality" => %{"score" => 6.0, "rationale" => "OK", "weight" => 0.10}
        }
      }

      {:ok, first} = Scoring.upsert_score(base_attrs)

      updated_attrs = Map.merge(base_attrs, %{
        composite_score: Decimal.new("8.1"),
        recommended_action: "advance",
        overall_rationale: "Revised after manual review."
      })

      {:ok, second} = Scoring.upsert_score(updated_attrs)

      assert second.id == first.id
      assert second.composite_score == Decimal.new("8.1")
      assert second.recommended_action == "advance"
    end

    test "returns error for invalid recommended_action" do
      company = insert(:company)
      user = insert(:user, company: company)
      job = insert(:job, company: company, created_by: user)
      candidate = insert(:candidate, company: company)
      application = insert(:application, job: job, candidate: candidate)
      session = insert(:video_session, application: application)

      attrs = %{
        application_id: application.id,
        video_session_id: session.id,
        composite_score: Decimal.new("7.0"),
        recommended_action: "maybe_hire",
        overall_rationale: "Test",
        scored_by: "gemini-1.5-pro",
        breakdown: %{}
      }

      assert {:error, changeset} = Scoring.upsert_score(attrs)
      assert %{recommended_action: [_]} = errors_on(changeset)
    end
  end

  describe "recompute_composite_score/1" do
    test "returns the sole score when only one session exists" do
      company = insert(:company)
      user = insert(:user, company: company)
      job = insert(:job, company: company, created_by: user)
      candidate = insert(:candidate, company: company)
      application = insert(:application, job: job, candidate: candidate)
      session = insert(:video_session, application: application)

      insert(:ai_score,
        application: application,
        video_session: session,
        composite_score: Decimal.new("7.5")
      )

      result = Scoring.recompute_composite_score(application.id)
      assert result != nil
      # Single score → recency weighting still returns 7.5
      assert Decimal.compare(result, Decimal.new("7.5")) == :eq
    end

    test "weights the most recent score more heavily with multiple sessions" do
      company = insert(:company)
      user = insert(:user, company: company)
      job = insert(:job, company: company, created_by: user)
      candidate = insert(:candidate, company: company)
      application = insert(:application, job: job, candidate: candidate)

      session_a = insert(:video_session, application: application,
                          inserted_at: ~U[2025-11-01 10:00:00Z])
      session_b = insert(:video_session, application: application,
                          inserted_at: ~U[2025-11-15 10:00:00Z])

      insert(:ai_score, application: application, video_session: session_a,
             composite_score: Decimal.new("5.0"))
      insert(:ai_score, application: application, video_session: session_b,
             composite_score: Decimal.new("9.0"))

      result = Scoring.recompute_composite_score(application.id)

      # Latest score (9.0) carries 2x weight: (5.0 * 1 + 9.0 * 2) / 3 = 7.666...
      assert Decimal.compare(result, Decimal.new("7.6")) == :gt
      assert Decimal.compare(result, Decimal.new("8.0")) == :lt
    end
  end

  describe "recompute_job_rankings/1" do
    test "assigns rank_within_job based on composite_score descending" do
      company = insert(:company)
      user = insert(:user, company: company)
      job = insert(:job, company: company, created_by: user)
      candidate_a = insert(:candidate, company: company)
      candidate_b = insert(:candidate, company: company)
      candidate_c = insert(:candidate, company: company)

      app_a = insert(:application, job: job, candidate: candidate_a, composite_score: Decimal.new("8.5"))
      app_b = insert(:application, job: job, candidate: candidate_b, composite_score: Decimal.new("6.0"))
      app_c = insert(:application, job: job, candidate: candidate_c, composite_score: Decimal.new("9.1"))

      Scoring.recompute_job_rankings(job.id)

      reloaded_a = Repo.get!(InterviewFlow.Candidates.Application, app_a.id)
      reloaded_b = Repo.get!(InterviewFlow.Candidates.Application, app_b.id)
      reloaded_c = Repo.get!(InterviewFlow.Candidates.Application, app_c.id)

      assert reloaded_c.rank_within_job == 1
      assert reloaded_a.rank_within_job == 2
      assert reloaded_b.rank_within_job == 3
    end
  end
end
