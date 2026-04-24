defmodule InterviewFlow.ApiKeys.ApiKey do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_scopes ~w(read write admin)

  schema "api_keys" do
    field :name, :string
    field :key_prefix, :string
    field :key_hash, :string
    field :scopes, {:array, :string}, default: ["read"]
    field :last_used_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec
    field :revoked_by, :binary_id

    belongs_to :organization, InterviewFlow.Organizations.Organization, foreign_key: :org_id
    belongs_to :created_by, InterviewFlow.Accounts.User, foreign_key: :created_by_id

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(api_key, attrs) do
    api_key
    |> cast(attrs, [:name, :scopes, :expires_at, :org_id, :created_by_id])
    |> validate_required([:name, :org_id, :created_by_id])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_scopes()
    |> validate_expiry()
  end

  defp validate_scopes(changeset) do
    validate_change(changeset, :scopes, fn _, scopes ->
      invalid = Enum.reject(scopes, &(&1 in @valid_scopes))
      if Enum.empty?(invalid), do: [], else: [{:scopes, "invalid scopes: #{Enum.join(invalid, ", ")}"}]
    end)
  end

  defp validate_expiry(changeset) do
    validate_change(changeset, :expires_at, fn _, expires_at ->
      if DateTime.compare(expires_at, DateTime.utc_now()) == :gt do
        []
      else
        [{:expires_at, "must be in the future"}]
      end
    end)
  end

  def active?(%__MODULE__{revoked_at: nil, expires_at: nil}), do: true
  def active?(%__MODULE__{revoked_at: nil, expires_at: exp}), do: DateTime.compare(exp, DateTime.utc_now()) == :gt
  def active?(_), do: false
end
