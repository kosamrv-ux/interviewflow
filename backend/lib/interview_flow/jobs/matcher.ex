defmodule InterviewFlow.Jobs.Matcher do
  @moduledoc """
  Computes a match score between a candidate's profile and a job's requirements.

  The score (0.0–1.0) is a weighted combination of:
  - Skills overlap (required vs candidate tags)
  - Experience level alignment
  - Location / remote preference compatibility
  - Availability (candidate available start date vs job's target start)

  This is a deterministic, rule-based pre-screen — the deeper AI scoring
  is performed post-interview by the Python scoring service.
  """

  alias InterviewFlow.Candidates.Candidate
  alias InterviewFlow.Jobs.Job

  @weights %{
    skills: 0.50,
    experience: 0.25,
    location: 0.15,
    availability: 0.10
  }

  @experience_levels ~w(intern junior mid senior staff principal)

  @doc """
  Returns a match result map for a candidate/job pair.

  ## Example

      %{
        score: 0.78,
        breakdown: %{skills: 0.90, experience: 0.75, location: 1.0, availability: 0.5},
        matched_skills: ["elixir", "postgresql"],
        missing_skills: ["kubernetes"]
      }
  """
  @spec match(Candidate.t(), Job.t()) :: map()
  def match(%Candidate{} = candidate, %Job{} = job) do
    skills_score = compute_skills(candidate.skills || [], job.required_skills || [])
    experience_score = compute_experience(candidate.experience_level, job.experience_level)
    location_score = compute_location(candidate, job)
    availability_score = compute_availability(candidate.available_from, job.target_start_date)

    breakdown = %{
      skills: skills_score,
      experience: experience_score,
      location: location_score,
      availability: availability_score
    }

    composite =
      Enum.reduce(breakdown, 0.0, fn {key, val}, acc ->
        acc + val * Map.fetch!(@weights, key)
      end)

    candidate_skills = normalize_list(candidate.skills || [])
    job_skills = normalize_list(job.required_skills || [])

    %{
      score: Float.round(composite, 4),
      breakdown: breakdown,
      matched_skills: Enum.filter(job_skills, &(&1 in candidate_skills)),
      missing_skills: Enum.reject(job_skills, &(&1 in candidate_skills))
    }
  end

  @doc "Ranks a list of candidates for a job, highest score first."
  @spec rank_candidates([Candidate.t()], Job.t()) :: [{Candidate.t(), map()}]
  def rank_candidates(candidates, job) do
    candidates
    |> Enum.map(fn c -> {c, match(c, job)} end)
    |> Enum.sort_by(fn {_c, result} -> result.score end, :desc)
  end

  # ── Dimension scorers ────────────────────────────────────────────────────

  defp compute_skills([], _required), do: 0.5
  defp compute_skills(_candidate, []), do: 1.0

  defp compute_skills(candidate_skills, required_skills) do
    candidate_set = normalize_list(candidate_skills)
    required_set = normalize_list(required_skills)

    matched = Enum.count(required_set, &(&1 in candidate_set))
    matched / length(required_set)
  end

  defp compute_experience(nil, _), do: 0.5
  defp compute_experience(_, nil), do: 0.5

  defp compute_experience(candidate_level, job_level) do
    c_idx = level_index(candidate_level)
    j_idx = level_index(job_level)

    if c_idx == :unknown or j_idx == :unknown do
      0.5
    else
      diff = abs(c_idx - j_idx)

      case diff do
        0 -> 1.0
        1 -> 0.75
        2 -> 0.50
        _ -> 0.25
      end
    end
  end

  defp compute_location(candidate, job) do
    cond do
      job.remote == true -> 1.0
      candidate.willing_to_relocate == true -> 1.0
      candidate.location == job.location -> 1.0
      true -> 0.0
    end
  end

  defp compute_availability(nil, _), do: 0.5
  defp compute_availability(_, nil), do: 1.0

  defp compute_availability(available_from, target_start) do
    diff_days = Date.diff(target_start, available_from)

    cond do
      diff_days >= 0 -> 1.0
      diff_days >= -14 -> 0.75
      diff_days >= -30 -> 0.50
      true -> 0.25
    end
  end

  defp level_index(level) do
    idx = Enum.find_index(@experience_levels, &(&1 == String.downcase(to_string(level))))
    if idx, do: idx, else: :unknown
  end

  defp normalize_list(list) do
    list
    |> Enum.map(&String.downcase(String.trim(to_string(&1))))
    |> Enum.uniq()
  end
end
