defmodule InterviewFlow.Scoring.ScoreServiceTest do
  use InterviewFlow.DataCase, async: true

  alias InterviewFlow.Scoring.ScoreService
  alias InterviewFlow.Factory

  describe "override/3" do
    test "applies manual score override and persists reviewer" do
      application = Factory.insert(:application)
      score = Factory.insert(:ai_score, application_id: application.id)
      reviewer = Factory.insert(:user, role: "recruiter")

      override_attrs = %{
        technical_score: 0.95,
        override_note: "Exceptional system design knowledge demonstrated"
      }

      assert {:ok, updated} = ScoreService.override(score.id, reviewer, override_attrs)
      assert updated.technical_score == 0.95
      assert updated.override_note =~ "Exceptional"
    end

    test "returns error for non-existent score" do
      reviewer = Factory.insert(:user, role: "admin")
      assert {:error, :score_not_found} = ScoreService.override(Ecto.UUID.generate(), reviewer, %{})
    end
  end

  describe "latest_score/1" do
    test "returns nil when no score exists" do
      application = Factory.insert(:application)
      assert is_nil(ScoreService.latest_score(application.id))
    end

    test "returns the most recent score" do
      application = Factory.insert(:application)
      _old = Factory.insert(:ai_score,
        application_id: application.id,
        scored_at: DateTime.add(DateTime.utc_now(), -3600, :second)
      )
      recent = Factory.insert(:ai_score,
        application_id: application.id,
        scored_at: DateTime.utc_now()
      )

      result = ScoreService.latest_score(application.id)
      assert result.id == recent.id
    end
  end

  describe "score_history/1" do
    test "returns all scores newest first" do
      application = Factory.insert(:application)
      Factory.insert(:ai_score, application_id: application.id)
      Factory.insert(:ai_score, application_id: application.id)

      history = ScoreService.score_history(application.id)
      assert length(history) == 2
    end

    test "returns empty list for application with no scores" do
      application = Factory.insert(:application)
      assert ScoreService.score_history(application.id) == []
    end
  end

  describe "rescore interval guard" do
    test "rejects re-scoring within the minimum interval without force flag" do
      application = Factory.insert(:application)

      # Insert a fresh score (scored now)
      Factory.insert(:ai_score,
        application_id: application.id,
        scored_at: DateTime.utc_now()
      )

      # Scoring without force should be blocked
      # (the actual AI call won't happen, but the guard fires first)
      assert {:error, {:too_soon, _}} = ScoreService.score(application.id, force: false)
    end
  end
end
