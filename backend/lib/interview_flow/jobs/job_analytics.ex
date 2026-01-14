defmodule InterviewFlow.Jobs.JobAnalytics do
  @moduledoc """
  Aggregates hiring funnel metrics for a job or across the company.

  Provides data for the recruiter dashboard:
  - Funnel conversion rates between pipeline stages
  - Time-in-stage averages
  - Source effectiveness (e.g., LinkedIn vs direct vs referral)
  - Offer acceptance rate
  """

  alias InterviewFlow.{Repo}
  alias InterviewFlow.Candidates.Application
  alias InterviewFlow.Interviews.Interview

  import Ecto.Query

  @pipeline_stages ~w(applied screening phone_screen technical onsite offer hired)

  @doc """
  Returns funnel conversion rates for a job.

  Example:
      %{
        applied: 120,
        screening: 45,
        phone_screen: 20,
        technical: 12,
        onsite: 6,
        offer: 3,
        hired: 2,
        rejection_count: 38,
        conversion_rate: 0.017,
        offer_acceptance_rate: 0.667
      }
  """
  @spec funnel(Ecto.UUID.t()) :: map()
  def funnel(job_id) do
    stage_counts =
      from(a in Application,
        where: a.job_id == ^job_id,
        group_by: a.stage,
        select: {a.stage, count(a.id)}
      )
      |> Repo.all()
      |> Map.new()

    base = Map.get(stage_counts, "applied", 0)
    hired = Map.get(stage_counts, "hired", 0)
    offers = Map.get(stage_counts, "offer", 0) + hired
    rejected = Map.get(stage_counts, "rejected", 0)

    stage_map =
      Enum.reduce(@pipeline_stages, %{}, fn stage, acc ->
        Map.put(acc, String.to_atom(stage), Map.get(stage_counts, stage, 0))
      end)

    %{
      stages: stage_map,
      rejection_count: rejected,
      conversion_rate: if(base > 0, do: Float.round(hired / base, 4), else: 0.0),
      offer_acceptance_rate: if(offers > 0, do: Float.round(hired / offers, 4), else: 0.0)
    }
  end

  @doc """
  Returns average days a candidate spent in each pipeline stage before
  either advancing or being rejected, for a given job.
  """
  @spec avg_time_in_stage(Ecto.UUID.t()) :: map()
  def avg_time_in_stage(job_id) do
    # Simplified: measure from applied_at to latest interview for proxy
    from(a in Application,
      left_join: i in Interview,
      on: i.application_id == a.id,
      where: a.job_id == ^job_id,
      group_by: a.stage,
      select: {
        a.stage,
        fragment("ROUND(AVG(EXTRACT(EPOCH FROM (? - ?))/86400), 1)", i.scheduled_at, a.applied_at)
      }
    )
    |> Repo.all()
    |> Map.new(fn {stage, avg} -> {stage, avg || 0.0} end)
  end

  @doc """
  Returns application counts grouped by source channel for a job.
  """
  @spec source_breakdown(Ecto.UUID.t()) :: [%{source: String.t(), count: integer()}]
  def source_breakdown(job_id) do
    from(a in Application,
      join: c in assoc(a, :candidate),
      where: a.job_id == ^job_id,
      group_by: c.source,
      select: %{source: coalesce(c.source, "direct"), count: count(a.id)},
      order_by: [desc: count(a.id)]
    )
    |> Repo.all()
  end

  @doc """
  Company-wide summary across all active jobs.
  """
  @spec company_summary(Ecto.UUID.t()) :: map()
  def company_summary(company_id) do
    total_applications =
      from(a in Application,
        join: j in assoc(a, :job),
        where: j.company_id == ^company_id
      )
      |> Repo.aggregate(:count, :id)

    active_applications =
      from(a in Application,
        join: j in assoc(a, :job),
        where: j.company_id == ^company_id and a.stage not in ["hired", "rejected"]
      )
      |> Repo.aggregate(:count, :id)

    hired_this_month =
      from(a in Application,
        join: j in assoc(a, :job),
        where:
          j.company_id == ^company_id and
            a.stage == "hired" and
            a.hired_at >= ^beginning_of_month()
      )
      |> Repo.aggregate(:count, :id)

    %{
      total_applications: total_applications,
      active_applications: active_applications,
      hired_this_month: hired_this_month
    }
  end

  defp beginning_of_month do
    today = Date.utc_today()
    Date.beginning_of_month(today) |> DateTime.new!(~T[00:00:00], "Etc/UTC")
  end
end
