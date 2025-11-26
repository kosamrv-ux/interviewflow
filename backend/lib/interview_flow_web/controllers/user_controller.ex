defmodule InterviewFlowWeb.UserController do
  use InterviewFlowWeb, :controller

  alias InterviewFlow.Accounts

  @doc "GET /api/v1/users/me"
  def me(conn, _params) do
    user = conn.assigns.current_user
    conn |> put_status(:ok) |> json(render_user(user))
  end

  @doc "PATCH /api/v1/users/me"
  def update_me(conn, params) do
    user = conn.assigns.current_user
    attrs = Map.take(params, ["full_name", "avatar_url"])

    case Accounts.update_user_profile(user, attrs) do
      {:ok, updated} ->
        conn |> put_status(:ok) |> json(render_user(updated))

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
    end
  end

  @doc "GET /api/v1/users — Admin only"
  def index(conn, _params) do
    company_id = conn.assigns.current_user.company_id
    users = Accounts.list_company_users(company_id)
    conn |> put_status(:ok) |> json(Enum.map(users, &render_user/1))
  end

  @doc "POST /api/v1/users/invite — Admin only"
  def invite(conn, params) do
    company_id = conn.assigns.current_user.company_id
    attrs = Map.take(params, ["email", "full_name", "role", "password", "password_confirmation"])

    case Accounts.invite_user(company_id, attrs) do
      {:ok, user} ->
        conn |> put_status(:created) |> json(render_user(user))

      {:error, changeset} ->
        conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(changeset)})
    end
  end

  @doc "PATCH /api/v1/users/:id/role — Admin only"
  def change_role(conn, %{"id" => user_id, "role" => role}) do
    company_id = conn.assigns.current_user.company_id

    case Accounts.get_user(company_id, user_id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{errors: [%{message: "User not found", code: "not_found"}]})

      user ->
        case Accounts.change_user_role(user, role) do
          {:ok, updated} -> conn |> put_status(:ok) |> json(render_user(updated))
          {:error, cs} -> conn |> put_status(:unprocessable_entity) |> json(%{errors: format_errors(cs)})
        end
    end
  end

  @doc "DELETE /api/v1/users/:id — Deactivates a user. Admin only."
  def deactivate(conn, %{"id" => user_id}) do
    company_id = conn.assigns.current_user.company_id
    actor = conn.assigns.current_user

    if user_id == actor.id do
      conn |> put_status(:conflict) |> json(%{errors: [%{message: "Cannot deactivate your own account", code: "conflict"}]})
    else
      case Accounts.get_user(company_id, user_id) do
        nil ->
          conn |> put_status(:not_found) |> json(%{errors: [%{message: "User not found", code: "not_found"}]})

        user ->
          {:ok, _} = Accounts.deactivate_user(user)
          send_resp(conn, :no_content, "")
      end
    end
  end

  defp render_user(user) do
    %{
      id: user.id,
      email: user.email,
      full_name: user.full_name,
      role: user.role,
      company_id: user.company_id,
      avatar_url: user.avatar_url,
      confirmed_at: user.confirmed_at,
      last_sign_in_at: user.last_sign_in_at,
      inserted_at: user.inserted_at
    }
  end

  defp format_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", to_string(v)) end)
    end)
    |> Enum.flat_map(fn {f, msgs} -> Enum.map(msgs, &%{field: to_string(f), message: &1, code: "invalid"}) end)
  end
end
