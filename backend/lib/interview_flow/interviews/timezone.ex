defmodule InterviewFlow.Interviews.Timezone do
  @moduledoc """
  Timezone normalization for interview scheduling.

  Bug discovered in production: interview scheduled_at was stored as the
  client-local naive datetime without UTC conversion. This caused interviews
  to appear at the wrong time for recruiters in different timezones and
  for the video room to open at incorrect times.

  Fix: all incoming datetimes are now normalized to UTC before storage.
  The candidate and recruiter's display timezone is stored separately
  (user preference in accounts) for frontend rendering only.

  Affected fields: scheduled_at, started_at, ended_at
  """

  @doc """
  Normalizes a datetime input to UTC.

  Accepts:
  - %DateTime{} already in UTC → returned as-is
  - %DateTime{} in non-UTC timezone → converted to UTC
  - ISO8601 string with timezone offset → parsed and converted
  - ISO8601 string without offset (naive) → assumed UTC with a warning log
  - Unix timestamp (integer) → converted from epoch
  """
  def to_utc(%DateTime{time_zone: "Etc/UTC"} = dt), do: {:ok, dt}

  def to_utc(%DateTime{} = dt) do
    {:ok, DateTime.shift_zone!(dt, "Etc/UTC")}
  rescue
    _ -> {:error, "invalid timezone in DateTime"}
  end

  def to_utc(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} ->
        to_utc(dt)

      {:error, :missing_offset} ->
        # Naive datetime string — treat as UTC but log a warning
        require Logger
        Logger.warning("[Timezone] received naive datetime string '#{str}', assuming UTC")

        case NaiveDateTime.from_iso8601(str) do
          {:ok, ndt} -> {:ok, DateTime.from_naive!(ndt, "Etc/UTC")}
          error -> error
        end

      {:error, reason} ->
        {:error, "invalid datetime string: #{reason}"}
    end
  end

  def to_utc(unix) when is_integer(unix) do
    case DateTime.from_unix(unix) do
      {:ok, dt} -> {:ok, dt}
      {:error, reason} -> {:error, "invalid unix timestamp: #{reason}"}
    end
  end

  def to_utc(nil), do: {:ok, nil}
  def to_utc(other), do: {:error, "unsupported datetime type: #{inspect(other)}"}

  @doc """
  Validates that scheduled_at is in the future.
  Adds a minimum buffer of 5 minutes to avoid scheduling in the past.
  """
  def validate_future(changeset, field) do
    import Ecto.Changeset

    validate_change(changeset, field, fn _, dt ->
      buffer = DateTime.add(DateTime.utc_now(), 5 * 60, :second)

      if DateTime.compare(dt, buffer) == :gt do
        []
      else
        [{field, "must be at least 5 minutes in the future"}]
      end
    end)
  end

  @doc """
  Formats a UTC datetime for display in the given IANA timezone.
  Falls back to UTC if the timezone is unknown.
  """
  def format_for_display(%DateTime{} = dt, tz) do
    case DateTime.shift_zone(dt, tz) do
      {:ok, local_dt} ->
        Calendar.strftime(local_dt, "%B %d, %Y at %I:%M %p %Z")

      {:error, _} ->
        Calendar.strftime(dt, "%B %d, %Y at %I:%M %p UTC")
    end
  end
end
