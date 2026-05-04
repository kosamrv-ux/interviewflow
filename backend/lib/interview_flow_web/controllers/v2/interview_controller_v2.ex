defmodule InterviewFlowWeb.V2.InterviewControllerV2 do
  @moduledoc """
  V2 interview endpoints.

  Key differences from V1:
  - Responses wrapped in `{data: ..., meta: ...}` envelope
  - Timestamps as ISO8601 strings
  - Status expanded: includes `no_show`, `rescheduled`
  - Supports `include` param to sideload candidate and job data
  - Filtering via query params: status, job_id, candidate_id, from, to
  - Sorting via `sort` param: `scheduled_at`, `-scheduled_at`, `created_at`
  """

  use InterviewFlowWeb, :controller

  alias InterviewFlow.Interviews
  alias InterviewFlow.Webhooks.Delivery

  action_fallback InterviewFlowWeb.V2.FallbackControllerV2

  def index(conn, params) do
    org_id = conn.assigns.org_id
    page = parse_int(params["page"], 1)
    per_page = min(parse_int(params["per_page"], 20), 100)

    filters = %{
      status: params["status"],
      job_id: params["job_id"],
      candidate_id: params["candidate_id"],
      from: parse_datetime(params["from"]),
      to: parse_datetime(params["to"])
    }

    sort = parse_sort(params["sort"], default: :scheduled_at)

    %{entries: interviews, total: total} =
      Interviews.list_for_org(org_id, filters, page: page, per_page: per_page, sort: sort)

    json(conn, %{
      data: Enum.map(interviews, &format_interview/1),
      meta: %{
        total: total,
        page: page,
        per_page: per_page,
        total_pages: ceil(total / per_page)
      }
    })
  end

  def show(conn, %{"id" => id}) do
    with {:ok, interview} <- Interviews.get_for_org(conn.assigns.org_id, id) do
      json(conn, %{data: format_interview(interview)})
    end
  end

  def create(conn, %{"interview" => params}) do
    org_id = conn.assigns.org_id

    with {:ok, interview} <- Interviews.create(Map.put(params, "org_id", org_id)) do
      Delivery.dispatch(org_id, "interview.scheduled", format_interview(interview))

      conn
      |> put_status(:created)
      |> json(%{data: format_interview(interview)})
    end
  end

  def update(conn, %{"id" => id, "interview" => params}) do
    with {:ok, interview} <- Interviews.get_for_org(conn.assigns.org_id, id),
         {:ok, updated} <- Interviews.update(interview, params) do
      json(conn, %{data: format_interview(updated)})
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, interview} <- Interviews.get_for_org(conn.assigns.org_id, id),
         {:ok, _} <- Interviews.delete(interview) do
      send_resp(conn, :no_content, "")
    end
  end

  def complete(conn, %{"id" => id}) do
    org_id = conn.assigns.org_id

    with {:ok, interview} <- Interviews.get_for_org(org_id, id),
         {:ok, completed} <- Interviews.mark_complete(interview) do
      Delivery.dispatch(org_id, "interview.completed", format_interview(completed))
      json(conn, %{data: format_interview(completed)})
    end
  end

  def cancel(conn, %{"id" => id} = params) do
    org_id = conn.assigns.org_id
    reason = params["reason"]

    with {:ok, interview} <- Interviews.get_for_org(org_id, id),
         {:ok, cancelled} <- Interviews.cancel(interview, reason) do
      Delivery.dispatch(org_id, "interview.cancelled", format_interview(cancelled))
      json(conn, %{data: format_interview(cancelled)})
    end
  end

  def recording(conn, %{"id" => id}) do
    with {:ok, interview} <- Interviews.get_for_org(conn.assigns.org_id, id),
         {:ok, url} <- Interviews.get_recording_url(interview) do
      json(conn, %{data: %{recording_url: url, expires_in: 3600}})
    end
  end

  ## Private

  defp format_interview(i) do
    %{
      id: i.id,
      status: i.status,
      scheduled_at: format_dt(i.scheduled_at),
      started_at: format_dt(i.started_at),
      ended_at: format_dt(i.ended_at),
      duration_minutes: i.duration_minutes,
      room_token: i.room_token,
      candidate_id: i.candidate_id,
      job_id: i.job_id,
      org_id: i.org_id,
      notes: i.notes,
      inserted_at: format_dt(i.inserted_at),
      updated_at: format_dt(i.updated_at)
    }
  end

  defp format_dt(nil), do: nil
  defp format_dt(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_dt(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt) <> "Z"

  defp parse_int(nil, default), do: default
  defp parse_int(str, default) do
    case Integer.parse(str) do
      {n, ""} -> n
      _ -> default
    end
  end

  defp parse_datetime(nil), do: nil
  defp parse_datetime(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse_sort(nil, default: field), do: {field, :asc}
  defp parse_sort("-" <> field, _), do: {String.to_existing_atom(field), :desc}
  defp parse_sort(field, _), do: {String.to_existing_atom(field), :asc}
end
