defmodule InterviewFlow.Accounts.InvitationService do
  @moduledoc """
  Service layer for team member invitations.

  Handles the full invitation flow:
  1. Create invitation record with secure token
  2. Send invitation email via SendInvitationWorker (async)
  3. Accept invitation — create user and consume token
  4. Resend invitation (rate-limited)
  5. Revoke pending invitation (admin only)

  Extracted from the UserController to enable consistent behavior
  between the HTTP API and potential future CLI/admin tools.
  """

  require Logger

  alias InterviewFlow.{Repo, Accounts}
  alias InterviewFlow.Accounts.{User, Invitation}
  alias InterviewFlow.Workers.SendInvitationWorker

  @max_pending_invitations 20

  @doc """
  Creates and sends an invitation to the given email address.

  Validates:
  - Email is not already a user in this company
  - There are no more than `@max_pending_invitations` pending invitations for the company
  """
  @spec invite(map(), map()) :: {:ok, Invitation.t()} | {:error, any()}
  def invite(%{email: email, role: role, company_id: company_id} = _attrs, actor) do
    with :ok <- check_not_existing_user(company_id, email),
         :ok <- check_pending_invitation_limit(company_id),
         {:ok, invitation} <- create_invitation(company_id, email, role, actor.id) do
      Logger.info("invitation_service: invitation created",
        invitation_id: invitation.id,
        email: email,
        role: role,
        invited_by: actor.id
      )

      # Enqueue email delivery asynchronously
      %{invitation_id: invitation.id}
      |> SendInvitationWorker.new(queue: :notifications)
      |> Oban.insert()

      {:ok, invitation}
    end
  end

  @doc """
  Accepts an invitation by token, creating the user account.

  Validates that the token is valid and not expired.
  """
  @spec accept(String.t(), map()) :: {:ok, User.t()} | {:error, any()}
  def accept(token, user_attrs) do
    with {:ok, invitation} <- find_valid_invitation(token) do
      Repo.transaction(fn ->
        {:ok, user} =
          Accounts.create_user(
            Map.merge(user_attrs, %{
              email: invitation.email,
              role: invitation.role,
              company_id: invitation.company_id
            })
          )

        consume_invitation(invitation)

        Logger.info("invitation_service: invitation accepted",
          invitation_id: invitation.id,
          user_id: user.id
        )

        user
      end)
    end
  end

  @doc "Revokes a pending invitation. Only admins can revoke."
  @spec revoke(Ecto.UUID.t(), map()) :: :ok | {:error, any()}
  def revoke(invitation_id, actor) do
    unless actor.role == "admin" do
      {:error, :forbidden}
    else
      case Repo.get(Invitation, invitation_id) do
        nil -> {:error, :not_found}
        inv -> Repo.delete(inv) && :ok
      end
    end
  end

  # ── Private helpers ──────────────────────────────────────────────────────

  defp check_not_existing_user(company_id, email) do
    case Accounts.find_user_by_email(company_id, email) do
      nil -> :ok
      _user -> {:error, "a user with this email already exists in your team"}
    end
  end

  defp check_pending_invitation_limit(company_id) do
    import Ecto.Query

    count =
      from(i in Invitation,
        where:
          i.company_id == ^company_id and
            i.expires_at > ^DateTime.utc_now() and
            is_nil(i.accepted_at)
      )
      |> Repo.aggregate(:count, :id)

    if count >= @max_pending_invitations,
      do: {:error, "pending invitation limit (#{@max_pending_invitations}) reached"},
      else: :ok
  end

  defp create_invitation(company_id, email, role, invited_by_id) do
    attrs = %{
      company_id: company_id,
      invited_by_id: invited_by_id,
      email: email,
      role: role
    }

    %Invitation{}
    |> Invitation.changeset(attrs)
    |> Repo.insert()
  end

  defp find_valid_invitation(token) do
    import Ecto.Query

    case Repo.one(
           from(i in Invitation,
             where:
               i.token == ^token and
                 i.expires_at > ^DateTime.utc_now() and
                 is_nil(i.accepted_at)
           )
         ) do
      nil -> {:error, :invalid_or_expired_token}
      inv -> {:ok, inv}
    end
  end

  defp consume_invitation(invitation) do
    invitation
    |> Ecto.Changeset.change(accepted_at: DateTime.utc_now())
    |> Repo.update!()
  end
end
