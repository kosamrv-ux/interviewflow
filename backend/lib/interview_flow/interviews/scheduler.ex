defmodule InterviewFlow.Interviews.Scheduler do
  @moduledoc """
  Business logic for scheduling interviews and resolving conflicts.

  Handles:
  - Availability checks (no double-booking for interviewer or candidate)
  - Buffer enforcement (minimum gap between consecutive interviews)
  - Timezone-aware slot validation
  - Capacity limits per interviewer per day
  """

  alias InterviewFlow.{Repo, Interviews}
  alias InterviewFlow.Interviews.Interview

  import Ecto.Query

  @min_duration_minutes 15
  @max_duration_minutes 240
  @buffer_minutes 15
  @max_interviews_per_interviewer_per_day 8

  @doc """
  Schedules a new interview after validating all business constraints.

  Returns `{:ok, interview}` or `{:error, reason}` / `{:error, changeset}`.
  """
  @spec schedule(map()) :: {:ok, Interview.t()} | {:error, any()}
  def schedule(attrs) do
    with :ok <- validate_duration(attrs),
         :ok <- validate_slot_in_future(attrs),
         :ok <- check_interviewer_availability(attrs),
         :ok <- check_candidate_availability(attrs),
         :ok <- check_daily_capacity(attrs) do
      Interviews.create_interview(attrs)
    end
  end

  @doc """
  Reschedules an existing interview to a new time slot.

  The old slot is freed before checking constraints for the new one.
  """
  @spec reschedule(Interview.t(), map()) :: {:ok, Interview.t()} | {:error, any()}
  def reschedule(%Interview{} = interview, new_attrs) do
    merged = Map.merge(interview_to_attrs(interview), new_attrs)

    with :ok <- validate_duration(merged),
         :ok <- validate_slot_in_future(merged),
         :ok <- check_interviewer_availability(merged, exclude_id: interview.id),
         :ok <- check_candidate_availability(merged, exclude_id: interview.id) do
      Interviews.update_interview(interview, new_attrs)
    end
  end

  @doc "Returns all scheduled slots for an interviewer on a given date."
  def interviewer_slots(interviewer_id, date) do
    start_of_day = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    end_of_day = DateTime.new!(date, ~T[23:59:59], "Etc/UTC")

    from(i in Interview,
      where:
        i.interviewer_id == ^interviewer_id and
          i.scheduled_at >= ^start_of_day and
          i.scheduled_at <= ^end_of_day and
          i.status not in ["cancelled"],
      order_by: i.scheduled_at,
      select: %{id: i.id, starts_at: i.scheduled_at, duration_minutes: i.duration_minutes}
    )
    |> Repo.all()
  end

  # ── Private validators ───────────────────────────────────────────────────

  defp validate_duration(%{duration_minutes: d}) when is_integer(d) do
    cond do
      d < @min_duration_minutes -> {:error, "duration must be at least #{@min_duration_minutes} minutes"}
      d > @max_duration_minutes -> {:error, "duration must not exceed #{@max_duration_minutes} minutes"}
      true -> :ok
    end
  end

  defp validate_duration(_), do: :ok

  defp validate_slot_in_future(%{scheduled_at: at}) when not is_nil(at) do
    if DateTime.compare(at, DateTime.utc_now()) == :gt,
      do: :ok,
      else: {:error, "interview must be scheduled in the future"}
  end

  defp validate_slot_in_future(_), do: :ok

  defp check_interviewer_availability(attrs, opts \\ []) do
    check_overlap(:interviewer_id, attrs, opts)
  end

  defp check_candidate_availability(attrs, opts \\ []) do
    check_overlap(:candidate_id_via_application, attrs, opts)
  end

  defp check_overlap(field, %{scheduled_at: starts_at, duration_minutes: duration} = attrs, opts)
       when not is_nil(starts_at) do
    person_id = Map.get(attrs, field)

    if is_nil(person_id) do
      :ok
    else
      ends_at = DateTime.add(starts_at, (duration + @buffer_minutes) * 60, :second)
      buffer_start = DateTime.add(starts_at, -@buffer_minutes * 60, :second)

      exclude_id = Keyword.get(opts, :exclude_id)

      query =
        from i in Interview,
          where:
            field(i, ^field) == ^person_id and
              i.status not in ["cancelled"] and
              i.scheduled_at < ^ends_at and
              datetime_add(i.scheduled_at, i.duration_minutes * 60, "second") > ^buffer_start

      query = if exclude_id, do: where(query, [i], i.id != ^exclude_id), else: query

      if Repo.exists?(query),
        do: {:error, "scheduling conflict: overlapping interview or insufficient buffer"},
        else: :ok
    end
  end

  defp check_overlap(_, _, _), do: :ok

  defp check_daily_capacity(%{interviewer_id: id, scheduled_at: at})
       when not is_nil(id) and not is_nil(at) do
    date = DateTime.to_date(at)
    slots = interviewer_slots(id, date)

    if length(slots) >= @max_interviews_per_interviewer_per_day,
      do: {:error, "interviewer has reached the daily interview limit of #{@max_interviews_per_interviewer_per_day}"},
      else: :ok
  end

  defp check_daily_capacity(_), do: :ok

  defp interview_to_attrs(interview) do
    %{
      interviewer_id: interview.interviewer_id,
      application_id: interview.application_id,
      scheduled_at: interview.scheduled_at,
      duration_minutes: interview.duration_minutes
    }
  end
end
