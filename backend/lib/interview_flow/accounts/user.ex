defmodule InterviewFlow.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @valid_roles ~w(admin recruiter interviewer stakeholder)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :email, :string
    field :email_encrypted, :binary
    field :hashed_password, :string, redact: true
    field :password, :string, virtual: true, redact: true
    field :password_confirmation, :string, virtual: true, redact: true
    field :full_name, :string
    field :avatar_url, :string
    field :role, :string, default: "recruiter"
    field :confirmed_at, :utc_datetime_usec
    field :last_sign_in_at, :utc_datetime_usec
    field :deactivated_at, :utc_datetime_usec

    belongs_to :company, InterviewFlow.Accounts.Company

    timestamps(type: :utc_datetime_usec)
  end

  @doc "Changeset for creating a new user with password."
  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :password, :password_confirmation, :full_name, :role, :company_id])
    |> validate_required([:email, :password, :full_name, :company_id])
    |> validate_email()
    |> validate_password()
    |> validate_inclusion(:role, @valid_roles)
    |> unique_constraint(:email)
  end

  @doc "Changeset for updating user profile fields (not password)."
  def profile_changeset(user, attrs) do
    user
    |> cast(attrs, [:full_name, :avatar_url])
    |> validate_required([:full_name])
    |> validate_length(:full_name, min: 2, max: 255)
  end

  @doc "Changeset for changing a user's role (admin only operation)."
  def role_changeset(user, attrs) do
    user
    |> cast(attrs, [:role])
    |> validate_required([:role])
    |> validate_inclusion(:role, @valid_roles)
  end

  @doc "Changeset for confirming a user's email address."
  def confirm_changeset(user) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    change(user, confirmed_at: now)
  end

  @doc "Records the current time as last_sign_in_at."
  def sign_in_changeset(user) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    change(user, last_sign_in_at: now)
  end

  defp validate_email(changeset) do
    changeset
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email address")
    |> validate_length(:email, max: 255)
    |> update_change(:email, &String.downcase/1)
  end

  defp validate_password(changeset) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72, message: "must be between 12 and 72 characters")
    |> validate_format(:password, ~r/[A-Z]/, message: "must contain at least one uppercase letter")
    |> validate_format(:password, ~r/[0-9]/, message: "must contain at least one number")
    |> validate_confirmation(:password, message: "does not match password")
    |> hash_password()
  end

  defp hash_password(%Ecto.Changeset{valid?: true, changes: %{password: password}} = changeset) do
    changeset
    |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
    |> delete_change(:password)
    |> delete_change(:password_confirmation)
  end

  defp hash_password(changeset), do: changeset

  @doc "Verifies the given password against the stored hash."
  def valid_password?(%__MODULE__{hashed_password: hashed}, password)
      when is_binary(hashed) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end
end
