defmodule InterviewFlow.Accounts.Company do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @valid_plans ~w(trial starter growth enterprise)
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "companies" do
    field :name, :string
    field :slug, :string
    field :domain, :string
    field :plan, :string, default: "trial"
    field :seats_limit, :integer, default: 5
    field :logo_url, :string
    field :settings, :map, default: %{}
    field :deleted_at, :utc_datetime_usec

    has_many :users, InterviewFlow.Accounts.User
    has_many :jobs, InterviewFlow.Jobs.Job

    timestamps(type: :utc_datetime_usec)
  end

  @doc "Changeset for creating a new company during registration."
  def registration_changeset(company, attrs) do
    company
    |> cast(attrs, [:name, :slug, :domain, :plan, :seats_limit, :logo_url, :settings])
    |> validate_required([:name, :slug])
    |> validate_length(:name, min: 2, max: 255)
    |> validate_length(:slug, min: 2, max: 100)
    |> validate_format(:slug, ~r/^[a-z0-9\-]+$/, message: "must be lowercase alphanumeric with hyphens only")
    |> validate_inclusion(:plan, @valid_plans)
    |> validate_number(:seats_limit, greater_than: 0)
    |> unique_constraint(:slug)
  end

  @doc "Changeset for updating company settings."
  def update_changeset(company, attrs) do
    company
    |> cast(attrs, [:name, :domain, :plan, :seats_limit, :logo_url, :settings])
    |> validate_required([:name])
    |> validate_length(:name, min: 2, max: 255)
    |> validate_inclusion(:plan, @valid_plans)
    |> validate_number(:seats_limit, greater_than: 0)
  end

  @doc "Generates a URL-safe slug from a company name."
  def slugify(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s\-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.trim("-")
  end
end
