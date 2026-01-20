defmodule InterviewFlow.Candidates.Export do
  @moduledoc """
  Exports candidate application data in CSV or JSON format.

  Used by recruiters to share shortlists with hiring managers outside
  the platform, or to import into ATS systems. PII fields are redacted
  for stakeholder exports based on the requesting user's role.
  """

  alias InterviewFlow.{Repo, Scoring.Ranking}
  alias InterviewFlow.Candidates.Application
  alias InterviewFlow.Scoring.AiScore

  import Ecto.Query

  @csv_headers ~w(
    rank candidate_name email phone location experience_level skills
    stage composite_score communication_score technical_score
    problem_solving_score applied_at
  )

  @doc """
  Exports applications for a job as CSV binary.

  When `redact_pii: true`, email and phone are replaced with "REDACTED".
  """
  @spec to_csv(Ecto.UUID.t(), Ecto.UUID.t(), keyword()) :: {:ok, String.t()} | {:error, any()}
  def to_csv(job_id, company_id, opts \\ []) do
    redact = Keyword.get(opts, :redact_pii, false)
    rows = fetch_rows(job_id, company_id)

    csv =
      [@csv_headers | Enum.map(rows, &row_to_csv_list(&1, redact))]
      |> Enum.map(&Enum.join(&1, ","))
      |> Enum.join("\n")

    {:ok, csv}
  end

  @doc """
  Exports applications for a job as a JSON-encodable list.
  """
  @spec to_json(Ecto.UUID.t(), Ecto.UUID.t(), keyword()) :: {:ok, [map()]} | {:error, any()}
  def to_json(job_id, company_id, opts \\ []) do
    redact = Keyword.get(opts, :redact_pii, false)
    rows = fetch_rows(job_id, company_id)
    {:ok, Enum.map(rows, &maybe_redact(&1, redact))}
  end

  # ── Private helpers ──────────────────────────────────────────────────────

  defp fetch_rows(job_id, _company_id) do
    from(a in Application,
      join: c in assoc(a, :candidate),
      left_join: s in AiScore,
      on: s.id == a.latest_ai_score_id,
      where: a.job_id == ^job_id,
      order_by: [asc_nulls_last: a.rank_within_job],
      select: %{
        rank: a.rank_within_job,
        candidate_name: c.full_name,
        email: c.email,
        phone: c.phone,
        location: c.location,
        experience_level: c.experience_level,
        skills: c.skills,
        stage: a.stage,
        composite_score: s.composite_score,
        communication_score: s.communication_score,
        technical_score: s.technical_score,
        problem_solving_score: s.problem_solving_score,
        applied_at: a.applied_at
      }
    )
    |> Repo.all()
  end

  defp row_to_csv_list(row, redact) do
    row = maybe_redact(row, redact)

    [
      row.rank || "",
      csv_escape(row.candidate_name),
      csv_escape(row.email),
      csv_escape(row.phone),
      csv_escape(row.location),
      row.experience_level || "",
      csv_escape(Enum.join(row.skills || [], "; ")),
      row.stage,
      format_score(row.composite_score),
      format_score(row.communication_score),
      format_score(row.technical_score),
      format_score(row.problem_solving_score),
      format_date(row.applied_at)
    ]
    |> Enum.map(&to_string/1)
  end

  defp maybe_redact(row, true) do
    Map.merge(row, %{email: "REDACTED", phone: "REDACTED"})
  end

  defp maybe_redact(row, _), do: row

  defp csv_escape(nil), do: ""

  defp csv_escape(str) do
    escaped = String.replace(to_string(str), "\"", "\"\"")
    if String.contains?(escaped, [",", "\"", "\n"]), do: "\"#{escaped}\"", else: escaped
  end

  defp format_score(nil), do: ""
  defp format_score(score), do: Float.round(score * 100, 1)

  defp format_date(nil), do: ""
  defp format_date(dt), do: DateTime.to_date(dt) |> Date.to_string()
end
