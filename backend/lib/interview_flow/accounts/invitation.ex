defmodule InterviewFlow.Accounts.Invitation do
  @moduledoc """
  Represents a pending invitation for a user to join a company workspace.

  Invitations are created when an admin sends an invite to a new email address
  that does not yet have an account.  The invitee clicks the email link, which
  contains the token, sets their password, and the invitation is consumed.

  Tokens are one-use and expire after 7 days.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  # Expiry window: 7 days in seconds
  @token_ttl_seconds 7 * 24 * 3600

  @valid_roles ~w(admin recruiter interviewer)

  schema "invitations" do
    belongs_to :company, InterviewFlow.Accounts.Company
    belongs_to :invited_by, InterviewFlow.Accounts.User, foreign_key: :invited_by_id

    field :email, :string
    field :full_name, :string
    field :role, :string, default: "recruiter"
    field :token, :string
    field :accepted_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec

    timestamps()
  end

  @doc "Creates a new invitation changeset, generating a secure token."
  def create_changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [:company_id, :invited_by_id, :email, :full_name, :role])
    |> validate_required([:company_id, :invited_by_id, :email, :role])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/, message: "must be a valid email address")
    |> validate_inclusion(:role, @valid_roles, message: "must be one of: #{Enum.join(@valid_roles, ", ")}")
    |> put_token()
    |> put_expiry()
    |> foreign_key_constraint(:company_id)
    |> foreign_key_constraint(:invited_by_id)
    |> unique_constraint([:company_id, :email],
         name: :invitations_company_id_email_index,
         message: "An active invitation already exists for this email")
  end

  @doc "Accepts the invitation, recording the accepted_at timestamp."
  def accept_changeset(invitation) do
    invitation
    |> change(accepted_at: DateTime.utc_now())
  end

  @doc "Returns true if the invitation token is still valid (not accepted, not expired)."
  def valid?(%__MODULE__{accepted_at: nil, expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :lt
  end

  def valid?(_invitation), do: false

  defp put_token(changeset) do
    token =
      :crypto.strong_rand_bytes(32)
      |> Base.url_encode64(padding: false)

    put_change(changeset, :token, token)
  end

  defp put_expiry(changeset) do
    expires_at = DateTime.add(DateTime.utc_now(), @token_ttl_seconds, :second)
    put_change(changeset, :expires_at, expires_at)
  end
end
