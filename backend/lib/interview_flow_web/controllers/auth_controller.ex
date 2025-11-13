defmodule InterviewFlowWeb.AuthController do
  use InterviewFlowWeb, :controller

  alias InterviewFlow.Accounts
  alias InterviewFlow.Accounts.Company
  alias InterviewFlow.Auth.Guardian
  alias InterviewFlowWeb.Auth.RateLimiter

  @doc """
  POST /api/v1/auth/register

  Registers a new company and its first admin user.
  Rate limited to prevent account-enumeration attacks.
  """
  def register(conn, params) do
    with :ok <- RateLimiter.check(conn, :auth_register),
         company_attrs <- Map.take(params, ["name", "slug", "domain"]),
         user_attrs <- Map.take(params, ["email", "password", "password_confirmation", "full_name"]),
         slug <- company_attrs["slug"] || Company.slugify(company_attrs["name"] || ""),
         company_attrs <- Map.put(company_attrs, "slug", slug),
         {:ok, %{company: _company, user: user}} <- Accounts.register_company(company_attrs, user_attrs),
         {:ok, tokens} <- Guardian.issue_token_pair(user) do
      conn
      |> put_status(:created)
      |> json(%{
        user: render_user(user),
        access_token: tokens.access_token,
        refresh_token: tokens.refresh_token,
        expires_in: tokens.expires_in,
        token_type: tokens.token_type
      })
    else
      {:error, :rate_limited} ->
        conn
        |> put_status(:too_many_requests)
        |> json(%{errors: [%{message: "Too many requests", code: "rate_limited"}], retry_after: 60})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_changeset_errors(changeset)})
    end
  end

  @doc """
  POST /api/v1/auth/login

  Authenticates a user and issues a JWT token pair.
  Returns 401 for both missing users and wrong passwords to prevent enumeration.
  """
  def login(conn, %{"email" => email, "password" => password}) do
    with :ok <- RateLimiter.check(conn, :auth_login),
         {:ok, user} <- Accounts.authenticate_user(email, password),
         {:ok, tokens} <- Guardian.issue_token_pair(user) do
      conn
      |> put_status(:ok)
      |> json(%{
        user: render_user(user),
        access_token: tokens.access_token,
        refresh_token: tokens.refresh_token,
        expires_in: tokens.expires_in,
        token_type: tokens.token_type
      })
    else
      {:error, :rate_limited} ->
        conn
        |> put_status(:too_many_requests)
        |> json(%{errors: [%{message: "Too many requests", code: "rate_limited"}], retry_after: 60})

      {:error, :invalid_credentials} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{errors: [%{message: "Invalid email or password", code: "unauthorized"}]})
    end
  end

  def login(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{errors: [%{message: "email and password are required", code: "bad_request"}]})
  end

  @doc """
  POST /api/v1/auth/refresh

  Exchanges a refresh token for a new token pair (rotation on each refresh).
  """
  def refresh(conn, %{"refresh_token" => refresh_token}) do
    with {:ok, user, _old_claims} <- Guardian.resource_from_token(refresh_token),
         {:ok, _} <- Guardian.revoke(refresh_token),
         {:ok, tokens} <- Guardian.issue_token_pair(user) do
      conn
      |> put_status(:ok)
      |> json(%{
        access_token: tokens.access_token,
        refresh_token: tokens.refresh_token,
        expires_in: tokens.expires_in,
        token_type: tokens.token_type
      })
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{errors: [%{message: "Invalid or expired refresh token", code: "unauthorized"}]})
    end
  end

  @doc """
  DELETE /api/v1/auth/logout

  Revokes the current access token.
  """
  def logout(conn, _params) do
    token = Guardian.Plug.current_token(conn)
    Guardian.revoke_token(token)

    conn
    |> put_status(:no_content)
    |> send_resp(:no_content, "")
  end

  # ─── Private helpers ─────────────────────────────────────────────────────

  defp render_user(user) do
    %{
      id: user.id,
      email: user.email,
      full_name: user.full_name,
      role: user.role,
      company_id: user.company_id,
      avatar_url: user.avatar_url,
      confirmed_at: user.confirmed_at,
      inserted_at: user.inserted_at
    }
  end

  defp format_changeset_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.flat_map(fn {field, messages} ->
      Enum.map(messages, fn message ->
        %{field: to_string(field), message: message, code: "invalid"}
      end)
    end)
  end
end
