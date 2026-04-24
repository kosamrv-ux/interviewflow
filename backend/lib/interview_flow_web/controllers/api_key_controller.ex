defmodule InterviewFlowWeb.ApiKeyController do
  use InterviewFlowWeb, :controller

  alias InterviewFlow.ApiKeys

  action_fallback InterviewFlowWeb.FallbackController

  def index(conn, _params) do
    keys = ApiKeys.list_api_keys(conn.assigns.org_id)
    json(conn, %{data: keys})
  end

  def create(conn, %{"api_key" => params}) do
    user = conn.assigns.current_user

    attrs =
      params
      |> Map.put("org_id", conn.assigns.org_id)
      |> Map.put("created_by_id", user.id)

    case ApiKeys.create_api_key(attrs) do
      {:ok, {api_key, raw_key}} ->
        conn
        |> put_status(:created)
        |> json(%{
          data: api_key,
          key: raw_key,
          notice: "Store this key securely — it will not be shown again."
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_errors(changeset)})
    end
  end

  def rotate(conn, %{"id" => id}) do
    user = conn.assigns.current_user
    key = ApiKeys.get_api_key!(conn.assigns.org_id, id)

    case ApiKeys.rotate_api_key(key, user.id) do
      {:ok, {new_key, raw_key}} ->
        json(conn, %{
          data: new_key,
          key: raw_key,
          notice: "Store this key securely — it will not be shown again."
        })

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: inspect(reason)})
    end
  end

  def revoke(conn, %{"id" => id}) do
    user = conn.assigns.current_user
    key = ApiKeys.get_api_key!(conn.assigns.org_id, id)

    case ApiKeys.revoke_api_key(key, user.id) do
      {:ok, _} -> send_resp(conn, :no_content, "")
      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_errors(changeset)})
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
