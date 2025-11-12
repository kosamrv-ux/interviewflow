defmodule InterviewFlow.Candidates.Candidate do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @valid_sources ~w(linkedin referral careers_page agency job_board indeed glassdoor other)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "candidates" do
    field :email, :string
    field :email_encrypted, :binary
    field :full_name, :string
    field :phone, :string
    field :phone_encrypted, :binary
    field :linkedin_url, :string
    field :github_url, :string
    field :portfolio_url, :string
    field :resume_url, :string
    field :resume_text, :string
    field :tags, {:array, :string}, default: []
    field :source, :string
    field :notes, :string
    field :deleted_at, :utc_datetime_usec

    belongs_to :company, InterviewFlow.Accounts.Company
    has_many :applications, InterviewFlow.Candidates.Application

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(candidate, attrs) do
    candidate
    |> cast(attrs, [
      :email, :full_name, :phone, :linkedin_url, :github_url,
      :portfolio_url, :resume_url, :resume_text, :tags, :source, :notes, :company_id
    ])
    |> validate_required([:email, :full_name, :company_id])
    |> validate_email()
    |> validate_length(:full_name, min: 2, max: 255)
    |> validate_url(:linkedin_url)
    |> validate_url(:github_url)
    |> validate_url(:portfolio_url)
    |> validate_inclusion(:source, @valid_sources, message: "is not a recognized source channel")
    |> unique_constraint([:company_id, :email], message: "a candidate with this email already exists")
    |> put_email_encrypted()
  end

  def resume_upload_changeset(candidate, attrs) do
    candidate
    |> cast(attrs, [:resume_url, :resume_text])
    |> validate_required([:resume_url])
  end

  defp validate_email(changeset) do
    changeset
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email address")
    |> validate_length(:email, max: 255)
    |> update_change(:email, &String.downcase/1)
  end

  defp validate_url(changeset, field) do
    validate_format(changeset, field, ~r|^https?://|, message: "must be a valid URL starting with http:// or https://")
  end

  # In a real implementation this would use Cloak to AES-encrypt the email.
  # For the skeleton we compute a placeholder binary — real encryption is wired in cloak_ecto config.
  defp put_email_encrypted(changeset) do
    case get_change(changeset, :email) do
      nil -> changeset
      email -> put_change(changeset, :email_encrypted, :crypto.hash(:sha256, email))
    end
  end
end
