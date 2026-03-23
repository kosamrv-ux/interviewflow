defmodule InterviewFlow.Accounts do
  @moduledoc """
  The Accounts context manages companies, users, authentication, and authorization.
  """

  import Ecto.Query, warn: false
  alias InterviewFlow.Repo
  alias InterviewFlow.Accounts.{Company, User}
  alias InterviewFlow.AuditLog

  # ─── Company ────────────────────────────────────────────────────────────────

  @doc """
  Registers a new company and its first admin user within a single transaction.
  Returns `{:ok, %{company: company, user: user}}` or `{:error, step, changeset, changes}`.
  """
  def register_company(company_attrs, user_attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:company, Company.registration_changeset(%Company{}, company_attrs))
    |> Ecto.Multi.insert(:user, fn %{company: company} ->
      %User{}
      |> User.registration_changeset(Map.put(user_attrs, "company_id", company.id))
      |> Ecto.Changeset.put_change(:role, "admin")
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{company: company, user: user}} -> {:ok, %{company: company, user: user}}
      {:error, _step, changeset, _changes} -> {:error, changeset}
    end
  end

  @doc """
  Returns a company by its ID, scoped to a company if provided.
  Returns nil if not found or soft-deleted.
  """
  def get_company(id) do
    Company
    |> where([c], c.id == ^id and is_nil(c.deleted_at))
    |> Repo.one()
  end

  @doc "Returns a company by its slug, or nil."
  def get_company_by_slug(slug) do
    Repo.get_by(Company, slug: slug, deleted_at: nil)
  end

  # ─── User ────────────────────────────────────────────────────────────────────

  @doc """
  Returns a user by email across all companies.
  Used for login where the company context is not yet known.
  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: String.downcase(email))
  end

  @doc "Returns a user by ID within a company."
  def get_user(company_id, user_id) do
    User
    |> where([u], u.id == ^user_id and u.company_id == ^company_id and is_nil(u.deactivated_at))
    |> Repo.one()
  end

  @doc """
  Authenticates a user by email and password with brute-force protection.

  Returns:
  - `{:ok, user}`               — successful authentication
  - `{:error, :invalid_credentials}` — wrong password (timing-safe)
  - `{:error, {:account_locked, locked_until}}` — account temporarily locked

  Security properties:
  - Always runs `Bcrypt.verify_pass/2` even for missing users (timing-safe).
  - Increments `failed_login_count` on failure; locks account for 15 minutes
    after 5 consecutive failures.
  - Resets `failed_login_count` and records `last_login_at` on success.
  - `locked_until` is compared server-side — client cannot clear the lock.
  """
  @max_login_attempts  5
  @lockout_minutes     15

  def authenticate_user(email, password) when is_binary(email) and is_binary(password) do
    user = get_user_by_email(email)

    # Always run bcrypt to prevent user-enumeration via timing
    cond do
      is_nil(user) ->
        Bcrypt.no_user_verify()
        {:error, :invalid_credentials}

      locked?(user) ->
        # Still verify password (timing safety) but return lock error
        User.valid_password?(user, password)
        {:error, {:account_locked, user.locked_until}}

      User.valid_password?(user, password) ->
        user
        |> User.sign_in_changeset()
        |> Repo.update!()
        |> then(&{:ok, &1})

      true ->
        record_failed_login(user)
        {:error, :invalid_credentials}
    end
  end

  defp locked?(%User{locked_until: nil}), do: false

  defp locked?(%User{locked_until: until}) do
    DateTime.compare(DateTime.utc_now(), until) == :lt
  end

  defp record_failed_login(%User{failed_login_count: count} = user) do
    new_count = count + 1

    attrs =
      if new_count >= @max_login_attempts do
        locked_until = DateTime.add(DateTime.utc_now(), @lockout_minutes * 60, :second)
        %{failed_login_count: new_count, locked_until: locked_until}
      else
        %{failed_login_count: new_count}
      end

    user
    |> Ecto.Changeset.change(attrs)
    |> Repo.update()

    AuditLog.log_security(user.id, "failed_login", %{
      attempt: new_count,
      locked: new_count >= @max_login_attempts
    })
  end

  @doc """
  Lists all active users in a company.
  """
  def list_company_users(company_id) do
    User
    |> where([u], u.company_id == ^company_id and is_nil(u.deactivated_at))
    |> order_by([u], [u.full_name])
    |> Repo.all()
  end

  @doc "Invites a new user to an existing company."
  def invite_user(company_id, attrs) do
    %User{}
    |> User.registration_changeset(Map.put(attrs, "company_id", company_id))
    |> Repo.insert()
  end

  @doc "Updates a user's profile fields."
  def update_user_profile(user, attrs) do
    user
    |> User.profile_changeset(attrs)
    |> Repo.update()
  end

  @doc "Changes a user's role (admin operation)."
  def change_user_role(user, role) do
    user
    |> User.role_changeset(%{role: role})
    |> Repo.update()
  end

  @doc "Deactivates a user (soft delete)."
  def deactivate_user(user) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    user
    |> Ecto.Changeset.change(deactivated_at: now)
    |> Repo.update()
  end

  @doc """
  Returns true if the user has any of the given roles.
  Used for authorization checks in controllers.
  """
  def has_role?(user, roles) when is_list(roles) do
    user.role in roles
  end

  def has_role?(user, role) when is_binary(role) do
    user.role == role
  end
end
