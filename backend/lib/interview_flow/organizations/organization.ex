defmodule InterviewFlow.Organizations.Organization do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_plans ~w(starter growth enterprise)
  @valid_sso_providers ~w(okta google_workspace azure_ad saml_generic)

  schema "organizations" do
    field :name, :string
    field :slug, :string
    field :plan, :string, default: "starter"
    field :settings, :map, default: %{}
    field :sso_enabled, :boolean, default: false
    field :sso_provider, :string
    field :sso_config, :map, default: %{}
    field :max_seats, :integer, default: 5

    has_many :users, InterviewFlow.Accounts.User, foreign_key: :org_id
    has_many :jobs, InterviewFlow.Jobs.Job, foreign_key: :org_id
    has_many :candidates, InterviewFlow.Candidates.Candidate, foreign_key: :org_id
    has_many :api_keys, InterviewFlow.ApiKeys.ApiKey, foreign_key: :org_id
    has_many :webhooks, InterviewFlow.Webhooks.Endpoint, foreign_key: :org_id

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(org, attrs) do
    org
    |> cast(attrs, [:name, :slug, :plan, :settings, :sso_enabled, :sso_provider, :sso_config, :max_seats])
    |> validate_required([:name, :slug, :plan])
    |> validate_length(:name, min: 2, max: 100)
    |> validate_format(:slug, ~r/^[a-z0-9\-]+$/, message: "must be lowercase alphanumeric with hyphens")
    |> validate_length(:slug, min: 2, max: 50)
    |> validate_inclusion(:plan, @valid_plans)
    |> validate_sso_config()
    |> unique_constraint(:slug)
  end

  defp validate_sso_config(changeset) do
    case get_field(changeset, :sso_enabled) do
      true ->
        changeset
        |> validate_required([:sso_provider])
        |> validate_inclusion(:sso_provider, @valid_sso_providers)

      _ ->
        changeset
    end
  end
end
