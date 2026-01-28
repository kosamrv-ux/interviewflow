defmodule InterviewFlow.Scoring.RankingTest do
  use InterviewFlow.DataCase, async: true

  alias InterviewFlow.Scoring.Ranking
  alias InterviewFlow.Factory

  describe "rerank_job/1" do
    test "assigns rank 1 to highest-scoring application" do
      job = Factory.insert(:job)

      app_high = Factory.insert(:application, job_id: job.id, stage: "technical")
      app_low = Factory.insert(:application, job_id: job.id, stage: "screening")

      Factory.insert(:ai_score, application_id: app_high.id, composite_score: 0.90)
      Factory.insert(:ai_score, application_id: app_low.id, composite_score: 0.60)

      {:ok, count} = Ranking.rerank_job(job.id)
      assert count == 2

      ranked = Ranking.ranked_list(job.id)
      top = hd(ranked)
      assert top.application_id == app_high.id
      assert top.rank == 1
    end

    test "excludes rejected applications from ranking" do
      job = Factory.insert(:job)

      active = Factory.insert(:application, job_id: job.id, stage: "technical")
      rejected = Factory.insert(:application, job_id: job.id, stage: "rejected")

      Factory.insert(:ai_score, application_id: active.id, composite_score: 0.75)
      Factory.insert(:ai_score, application_id: rejected.id, composite_score: 0.85)

      ranked = Ranking.ranked_list(job.id)
      ids = Enum.map(ranked, & &1.application_id)

      assert active.id in ids
      refute rejected.id in ids
    end

    test "applications without scores appear at the end" do
      job = Factory.insert(:job)

      scored = Factory.insert(:application, job_id: job.id, stage: "onsite")
      unscored = Factory.insert(:application, job_id: job.id, stage: "applied")

      Factory.insert(:ai_score, application_id: scored.id, composite_score: 0.80)

      ranked = Ranking.ranked_list(job.id)
      ids = Enum.map(ranked, & &1.application_id)

      assert hd(ids) == scored.id
    end
  end

  describe "percentile/1" do
    test "returns nil for a single-application pool" do
      job = Factory.insert(:job)
      app = Factory.insert(:application, job_id: job.id)
      assert is_nil(Ranking.percentile(app.id))
    end

    test "top-ranked candidate has percentile near 100" do
      job = Factory.insert(:job)

      apps =
        for score <- [0.95, 0.80, 0.70, 0.60] do
          app = Factory.insert(:application, job_id: job.id, stage: "technical")
          Factory.insert(:ai_score, application_id: app.id, composite_score: score)
          app
        end

      {:ok, _} = Ranking.rerank_job(job.id)
      top = hd(apps)
      pct = Ranking.percentile(top.id)

      assert pct != nil
      assert pct >= 90.0
    end

    test "returns nil for a non-existent application" do
      assert is_nil(Ranking.percentile(Ecto.UUID.generate()))
    end
  end

  describe "top_candidates/2" do
    test "returns at most N candidates" do
      job = Factory.insert(:job)

      for i <- 1..5 do
        app = Factory.insert(:application, job_id: job.id, stage: "onsite")
        Factory.insert(:ai_score, application_id: app.id, composite_score: i / 10.0)
      end

      top = Ranking.top_candidates(job.id, 3)
      assert length(top) == 3
    end
  end
end
