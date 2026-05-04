defmodule InterviewFlowWeb.V2.FallbackControllerV2 do
  @moduledoc """
  V2 fallback controller with structured error responses.

  All errors use the format:
    {
      "errors": [
        {"code": "not_found", "message": "Interview not found"},
        {"code": "validation_error", "field": "scheduled_at", "message": "can't be blank"}
      ]
    }
  """

  use Phoenix.Controller

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> json(%{errors: [%{code: "not_found", message: "Resource not found"}]})
  end

  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(:unauthorized)
    |> json(%{errors: [%{code: "unauthorized", message: "Authentication required"}]})
  end

  def call(conn, {:error, :forbidden}) do
    conn
    |> put_status(:forbidden)
    |> json(%{errors: [%{code: "forbidden", message: "Insufficient permissions"}]})
  end

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Enum.reduce(opts, msg, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", to_string(value))
        end)
      end)
      |> Enum.flat_map(fn {field, messages} ->
        Enum.map(messages, fn message ->
          %{code: "validation_error", field: to_string(field), message: message}
        end)
      end)

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: errors})
  end

  def call(conn, {:error, reason}) when is_binary(reason) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: [%{code: "error", message: reason}]})
  end

  def call(conn, {:error, _reason}) do
    conn
    |> put_status(:internal_server_error)
    |> json(%{errors: [%{code: "internal_error", message: "An unexpected error occurred"}]})
  end
end
