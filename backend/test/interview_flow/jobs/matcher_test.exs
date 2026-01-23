defmodule InterviewFlow.Jobs.MatcherTest do
  use ExUnit.Case, async: true

  alias InterviewFlow.Jobs.Matcher

  defp job(attrs \\ %{}) do
    Map.merge(
      %{
        id: Ecto.UUID.generate(),
        title: "Senior Elixir Engineer",
        required_skills: ["elixir", "postgresql", "kubernetes"],
        experience_level: "senior",
        location: "New York",
        remote: false,
        target_start_date: Date.utc_today() |> Date.add(30)
      },
      attrs
    )
  end

  defp candidate(attrs \\ %{}) do
    Map.merge(
      %{
        id: Ecto.UUID.generate(),
        full_name: "Jane Doe",
        skills: ["elixir", "postgresql", "docker"],
        experience_level: "senior",
        location: "New York",
        willing_to_relocate: false,
        available_from: Date.utc_today() |> Date.add(7)
      },
      attrs
    )
  end

  describe "match/2" do
    test "returns a score map with expected keys" do
      result = Matcher.match(candidate(), job())
      assert Map.has_key?(result, :score)
      assert Map.has_key?(result, :breakdown)
      assert Map.has_key?(result, :matched_skills)
      assert Map.has_key?(result, :missing_skills)
    end

    test "score is between 0 and 1" do
      result = Matcher.match(candidate(), job())
      assert result.score >= 0.0
      assert result.score <= 1.0
    end

    test "perfect match returns high score" do
      c = candidate(%{skills: ["elixir", "postgresql", "kubernetes"], experience_level: "senior"})
      j = job(%{required_skills: ["elixir", "postgresql", "kubernetes"], experience_level: "senior"})
      result = Matcher.match(c, j)
      assert result.score > 0.8
    end

    test "no skill overlap returns low skills score" do
      c = candidate(%{skills: ["java", "spring"]})
      j = job(%{required_skills: ["elixir", "postgresql", "kubernetes"]})
      result = Matcher.match(c, j)
      assert result.breakdown.skills == 0.0
    end

    test "identifies matched and missing skills correctly" do
      c = candidate(%{skills: ["elixir", "docker"]})
      j = job(%{required_skills: ["elixir", "postgresql", "kubernetes"]})
      result = Matcher.match(c, j)
      assert "elixir" in result.matched_skills
      assert "postgresql" in result.missing_skills
      assert "kubernetes" in result.missing_skills
    end

    test "remote job gives full location score regardless of location mismatch" do
      c = candidate(%{location: "Los Angeles", willing_to_relocate: false})
      j = job(%{location: "New York", remote: true})
      result = Matcher.match(c, j)
      assert result.breakdown.location == 1.0
    end

    test "experience level mismatch reduces score" do
      c = candidate(%{experience_level: "junior"})
      j = job(%{experience_level: "senior"})
      result = Matcher.match(c, j)
      assert result.breakdown.experience < 0.75
    end

    test "handles nil skills gracefully" do
      c = candidate(%{skills: nil})
      result = Matcher.match(c, job())
      assert result.score >= 0.0
    end
  end

  describe "rank_candidates/2" do
    test "returns candidates sorted by score descending" do
      j = job()

      c1 = candidate(%{id: "c1", skills: ["elixir", "postgresql", "kubernetes"]})
      c2 = candidate(%{id: "c2", skills: ["java"]})
      c3 = candidate(%{id: "c3", skills: ["elixir", "postgresql"]})

      ranked = Matcher.rank_candidates([c1, c2, c3], j)
      scores = Enum.map(ranked, fn {_c, r} -> r.score end)
      assert scores == Enum.sort(scores, :desc)
    end

    test "returns a list of {candidate, result} tuples" do
      ranked = Matcher.rank_candidates([candidate()], job())
      assert [{_c, result}] = ranked
      assert Map.has_key?(result, :score)
    end
  end
end
