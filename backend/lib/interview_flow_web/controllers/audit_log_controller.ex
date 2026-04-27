defmodule InterviewFlowWeb.AuditLogController do
  @moduledoc """
  Enterprise audit log viewer endpoint.

  Provides paginated, filterable access to the organization's audit log.
  Only available to users with admin or owner role.

  Query parameters:
    - page (integer, default 1)
    - per_page (integer, default 50, max 200)
    - actor_id (uuid, filter by user)
    - action (string, filter by action type)
    - resource_type (string, e.g. "interview", "candidate")
    - from (ISO8601 datetime)
    - to (ISO8601 datetime)
  """

  use InterviewFlowWeb, :controller

  alias InterviewFlow.AuditLog

  action_fallback InterviewFlowWeb.FallbackController

  def index(conn, params) do
    org_id = conn.assigns.org_id

    filters = %{
      actor_id: params["actor_id"],
      action: params["action"],
      resource_type: params["resource_type"],
      from: parse_datetime(params["from"]),
      to: parse_datetime(params["to"])
    }

    page = Map.get(params, "page", "1") |> String.to_integer()
    per_page = min(Map.get(params, "per_page", "50") |> String.to_integer(), 200)

    %{entries: entries, total: total, page: page, per_page: per_page} =
      AuditLog.list_for_org(org_id, filters, page: page, per_page: per_page)

    json(conn, %{
      data: entries,
      meta: %{
        total: total,
        page: page,
        per_page: per_page,
        total_pages: ceil(total / per_page)
      }
    })
  end

  def show(conn, %{"id" => id}) do
    entry = AuditLog.get_entry!(conn.assigns.org_id, id)
    json(conn, %{data: entry})
  end

  def export(conn, params) do
    org_id = conn.assigns.org_id
    format = Map.get(params, "format", "json")

    entries = AuditLog.export_for_org(org_id, %{
      from: parse_datetime(params["from"]),
      to: parse_datetime(params["to"])
    })

    case format do
      "csv" ->
        csv = AuditLog.to_csv(entries)
        conn
        |> put_resp_content_type("text/csv")
        |> put_resp_header("content-disposition", "attachment; filename=\"audit-log.csv\"")
        |> send_resp(200, csv)

      _ ->
        json(conn, %{data: entries})
    end
  end

  defp parse_datetime(nil), do: nil
  defp parse_datetime(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end
end
