defmodule InterviewFlow.Organizations do
  @moduledoc """
  Context for multi-tenant organization management.

  All resources (jobs, candidates, interviews, applications) are scoped
  to an organization. This context provides functions for managing orgs
  and enforcing tenant isolation at the data layer.
  """

  import Ecto.Query, warn: false

  alias InterviewFlow.Repo
  alias InterviewFlow.Organizations.{Organization, Membership}

  @doc """
  Returns an organization by id, raising if not found.
  """
  def get_organization!(id), do: Repo.get!(Organization, id)

  @doc """
  Returns an organization by slug.
  """
  def get_organization_by_slug(slug) do
    Repo.get_by(Organization, slug: slug)
  end

  @doc """
  Creates a new organization with the given attributes.
  The creating user is automatically assigned the :owner role.
  """
  def create_organization(attrs, owner_user) do
    Repo.transaction(fn ->
      with {:ok, org} <- %Organization{} |> Organization.changeset(attrs) |> Repo.insert(),
           {:ok, _membership} <- add_member(org, owner_user, :owner) do
        org
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Updates an organization's settings.
  """
  def update_organization(%Organization{} = org, attrs) do
    org
    |> Organization.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Lists all members of an organization.
  """
  def list_members(%Organization{id: org_id}) do
    from(u in InterviewFlow.Accounts.User,
      where: u.org_id == ^org_id,
      select: %{id: u.id, email: u.email, name: u.name, role: u.org_role, inserted_at: u.inserted_at}
    )
    |> Repo.all()
  end

  @doc """
  Adds a user to an organization with the given role.
  Valid roles: :owner, :admin, :member, :viewer
  """
  def add_member(%Organization{id: org_id}, user, role \\ :member) do
    user
    |> Ecto.Changeset.change(%{org_id: org_id, org_role: to_string(role)})
    |> Repo.update()
  end

  @doc """
  Removes a user from an organization. Owners cannot be removed unless
  another owner exists.
  """
  def remove_member(%Organization{id: org_id} = org, user) do
    if user.org_role == "owner" && count_owners(org) <= 1 do
      {:error, :last_owner}
    else
      user
      |> Ecto.Changeset.change(%{org_id: nil, org_role: nil})
      |> Repo.update()
    end
  end

  @doc """
  Checks whether a user belongs to the given organization.
  """
  def member?(%Organization{id: org_id}, user) do
    user.org_id == org_id
  end

  @doc """
  Checks whether a user has at least the given role within their organization.
  Role hierarchy: owner > admin > member > viewer
  """
  def has_role?(user, required_role) do
    role_weight = %{"owner" => 4, "admin" => 3, "member" => 2, "viewer" => 1}
    (role_weight[user.org_role] || 0) >= (role_weight[to_string(required_role)] || 0)
  end

  @doc """
  Returns organization-level stats for the dashboard.
  """
  def org_stats(%Organization{id: org_id}) do
    %{
      total_jobs: count_by_org(InterviewFlow.Jobs.Job, org_id),
      total_candidates: count_by_org(InterviewFlow.Candidates.Candidate, org_id),
      total_interviews: count_by_org(InterviewFlow.Interviews.Interview, org_id),
      member_count: count_by_org(InterviewFlow.Accounts.User, org_id, :org_id)
    }
  end

  ## Private helpers

  defp count_owners(%Organization{id: org_id}) do
    from(u in InterviewFlow.Accounts.User,
      where: u.org_id == ^org_id and u.org_role == "owner",
      select: count()
    )
    |> Repo.one()
  end

  defp count_by_org(schema, org_id, field \\ :org_id) do
    from(r in schema, where: field(r, ^field) == ^org_id, select: count())
    |> Repo.one()
  end
end
