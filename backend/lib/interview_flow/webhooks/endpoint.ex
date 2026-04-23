defmodule InterviewFlow.Webhooks.Endpoint do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_events ~w(
    interview.scheduled interview.completed interview.cancelled
    candidate.created candidate.updated candidate.rejected
    application.submitted application.stage_changed
    scoring.completed ranking.updated
  )

  schema "webhook_endpoints" do
    field :url, :string
    field :secret, :string
    field :events, {:array, :string}, default: []
    field :enabled, :boolean, default: true
    field :description, :string
    field :last_triggered_at, :utc_datetime_usec
    field :failure_count, :integer, default: 0

    belongs_to :organization, InterviewFlow.Organizations.Organization, foreign_key: :org_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(endpoint, attrs) do
    endpoint
    |> cast(attrs, [:url, :secret, :events, :enabled, :description, :org_id])
    |> validate_required([:url, :org_id])
    |> validate_url(:url)
    |> validate_events(:events)
    |> put_secret_if_missing()
    |> unique_constraint([:org_id, :url])
  end

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn _, url ->
      case URI.parse(url) do
        %URI{scheme: s} when s in ["http", "https"] -> []
        _ -> [{field, "must be a valid http or https URL"}]
      end
    end)
  end

  defp validate_events(changeset, field) do
    validate_change(changeset, field, fn _, events ->
      invalid = Enum.reject(events, &(&1 in @valid_events))

      if Enum.empty?(invalid) do
        []
      else
        [{field, "invalid events: #{Enum.join(invalid, ", ")}"}]
      end
    end)
  end

  defp put_secret_if_missing(changeset) do
    if get_field(changeset, :secret) do
      changeset
    else
      put_change(changeset, :secret, generate_secret())
    end
  end

  defp generate_secret do
    :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
  end

  def valid_events, do: @valid_events
end
