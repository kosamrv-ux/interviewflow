defmodule InterviewFlow.Candidates.PipelineTest do
  use InterviewFlow.DataCase, async: true

  alias InterviewFlow.Candidates.Pipeline
  alias InterviewFlow.Factory

  describe "advance/1" do
    test "advances application from applied to screening" do
      app = Factory.insert(:application, stage: "applied")
      assert {:ok, updated} = Pipeline.advance(app)
      assert updated.stage == "screening"
    end

    test "advances through each stage in order" do
      stages = Pipeline.stages()

      Enum.zip(stages, tl(stages))
      |> Enum.each(fn {from, to} ->
        # Skip the scoring-gated transition for this test
        unless from == "phone_screen" do
          app = Factory.insert(:application, stage: from)
          assert {:ok, updated} = Pipeline.advance(app)
          assert updated.stage == to, "Expected #{from} -> #{to}, got #{updated.stage}"
        end
      end)
    end

    test "cannot advance a rejected application" do
      app = Factory.insert(:application, stage: "rejected")
      assert {:error, "cannot advance a rejected application"} = Pipeline.advance(app)
    end

    test "cannot advance a hired application" do
      app = Factory.insert(:application, stage: "hired")
      assert {:error, "application has already been hired"} = Pipeline.advance(app)
    end

    test "cannot advance past phone_screen without an AI score" do
      app = Factory.insert(:application, stage: "phone_screen")
      # No AI score exists
      assert {:error, msg} = Pipeline.advance(app)
      assert msg =~ "AI score is required"
    end

    test "advances past phone_screen when AI score exists" do
      app = Factory.insert(:application, stage: "phone_screen")
      _score = Factory.insert(:ai_score, application_id: app.id)
      # Update app to reference the score
      app = %{app | latest_ai_score_id: _score.id}

      assert {:ok, updated} = Pipeline.advance(app)
      assert updated.stage == "technical"
    end
  end

  describe "reject/2" do
    test "rejects an active application" do
      app = Factory.insert(:application, stage: "screening")
      assert {:ok, updated} = Pipeline.reject(app, "underqualified")
      assert updated.stage == "rejected"
    end

    test "sets rejection reason when provided" do
      app = Factory.insert(:application, stage: "technical")
      {:ok, updated} = Pipeline.reject(app, "failed_assessment")
      assert updated.rejection_reason == "failed_assessment"
    end

    test "cannot reject a hired candidate" do
      app = Factory.insert(:application, stage: "hired")
      assert {:error, "cannot reject a hired candidate"} = Pipeline.reject(app)
    end
  end

  describe "hire/1" do
    test "hires an application in offer stage" do
      app = Factory.insert(:application, stage: "offer")
      assert {:ok, updated} = Pipeline.hire(app)
      assert updated.stage == "hired"
      assert updated.hired_at != nil
    end

    test "cannot hire from a stage before offer" do
      for stage <- ~w(applied screening phone_screen technical onsite) do
        app = Factory.insert(:application, stage: stage)
        assert {:error, msg} = Pipeline.hire(app)
        assert msg =~ "offer stage"
      end
    end
  end

  describe "pipeline_counts/1" do
    test "returns zero counts for all stages when no applications exist" do
      job = Factory.insert(:job)
      counts = Pipeline.pipeline_counts(job.id)
      assert Map.get(counts, "applied") == 0
      assert Map.get(counts, "rejected") == 0
    end

    test "returns correct counts for each stage" do
      job = Factory.insert(:job)
      Factory.insert(:application, job_id: job.id, stage: "applied")
      Factory.insert(:application, job_id: job.id, stage: "applied")
      Factory.insert(:application, job_id: job.id, stage: "screening")
      Factory.insert(:application, job_id: job.id, stage: "rejected")

      counts = Pipeline.pipeline_counts(job.id)
      assert counts["applied"] == 2
      assert counts["screening"] == 1
      assert counts["rejected"] == 1
      assert counts["technical"] == 0
    end
  end
end
