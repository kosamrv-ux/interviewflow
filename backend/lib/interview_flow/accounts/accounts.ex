defmodule InterviewFlow.Accounts do
  @moduledoc """
  The Accounts context manages companies, users, authentication, and authorization.
  """

  import Ecto.Query, warn: false
  alias InterviewFlow.Repo
  alias InterviewFlow.Accounts.{Company, User}

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
  Authenticates a user by email and password.
  Returns `{:ok, user}` on success, `{:error, :invalid_credentials}` on failure.
  Timing-safe: always runs bcrypt even for missing users.
  """
  def authenticate_user(email, password) when is_binary(email) and is_binary(password) do
    user = get_user_by_email(email)

    if User.valid_password?(user, password) do
      {:ok, Repo.update!(User.sign_in_changeset(user))}
    else
      {:error, :invalid_credentials}
    end
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
