defmodule InterviewFlowWeb.WebhookController do
  use InterviewFlowWeb, :controller

  alias InterviewFlow.Webhooks
  alias InterviewFlow.Webhooks.{Endpoint, Delivery}

  action_fallback InterviewFlowWeb.FallbackController

  def index(conn, _params) do
    org_id = conn.assigns.org_id
    endpoints = Webhooks.list_endpoints(org_id)
    json(conn, %{data: endpoints})
  end

  def create(conn, %{"webhook" => params}) do
    org_id = conn.assigns.org_id

    with {:ok, endpoint} <- Webhooks.create_endpoint(Map.put(params, "org_id", org_id)) do
      conn
      |> put_status(:created)
      |> json(%{data: endpoint})
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, endpoint} <- Webhooks.get_endpoint(conn.assigns.org_id, id) do
      json(conn, %{data: endpoint})
    end
  end

  def update(conn, %{"id" => id, "webhook" => params}) do
    with {:ok, endpoint} <- Webhooks.get_endpoint(conn.assigns.org_id, id),
         {:ok, updated} <- Webhooks.update_endpoint(endpoint, params) do
      json(conn, %{data: updated})
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, endpoint} <- Webhooks.get_endpoint(conn.assigns.org_id, id),
         {:ok, _} <- Webhooks.delete_endpoint(endpoint) do
      send_resp(conn, :no_content, "")
    end
  end

  def test_delivery(conn, %{"id" => id}) do
    with {:ok, endpoint} <- Webhooks.get_endpoint(conn.assigns.org_id, id) do
      test_payload = %{message: "test delivery", timestamp: DateTime.utc_now()}

      case Delivery.deliver(endpoint.id, "webhook.test", test_payload) do
        {:ok, status_code} ->
          json(conn, %{success: true, status_code: status_code})

        {:error, reason} ->
          conn
          |> put_status(:bad_gateway)
          |> json(%{success: false, error: to_string(reason)})
      end
    end
  end

  def delivery_logs(conn, %{"id" => id} = params) do
    with {:ok, _endpoint} <- Webhooks.get_endpoint(conn.assigns.org_id, id) do
      page = Map.get(params, "page", "1") |> String.to_integer()
      logs = Webhooks.list_delivery_logs(id, page: page)
      json(conn, %{data: logs})
    end
  end
end
