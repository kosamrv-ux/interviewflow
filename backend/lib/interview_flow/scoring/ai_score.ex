defmodule InterviewFlow.Scoring.AiScore do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @valid_statuses ~w(pending completed failed overridden)
  @valid_actions ~w(advance reject hold)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "ai_scores" do
    field :scored_by, :string, default: "vertex_ai_gemini_1_5_pro"
    field :model_version, :string
    field :composite_score, :decimal
    field :breakdown, :map
    field :strengths, {:array, :string}
    field :areas_for_growth, {:array, :string}
    field :recommended_action, :string
    field :confidence, :decimal
    field :prompt_version, :string
    field :raw_response, :string
    field :processing_ms, :integer
    field :status, :string, default: "completed"

    belongs_to :application, InterviewFlow.Candidates.Application
    belongs_to :video_session, InterviewFlow.Interviews.VideoSession
    belongs_to :overridden_by, InterviewFlow.Accounts.User, foreign_key: :overridden_by_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(score, attrs) do
    score
    |> cast(attrs, [
      :application_id, :video_session_id, :scored_by, :model_version,
      :composite_score, :breakdown, :strengths, :areas_for_growth,
      :recommended_action, :confidence, :prompt_version, :raw_response,
      :processing_ms, :status
    ])
    |> validate_required([:application_id, :composite_score, :breakdown, :status])
    |> validate_number(:composite_score, greater_than_or_equal_to: 0, less_than_or_equal_to: 10)
    |> validate_number(:confidence, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_inclusion(:recommended_action, @valid_actions)
    |> validate_breakdown_structure()
  end

  def override_changeset(score, override_attrs, user_id) do
    score
    |> cast(override_attrs, [:composite_score, :breakdown, :recommended_action, :strengths, :areas_for_growth])
    |> put_change(:status, "overridden")
    |> put_change(:overridden_by_id, user_id)
    |> validate_number(:composite_score, greater_than_or_equal_to: 0, less_than_or_equal_to: 10)
    |> validate_inclusion(:recommended_action, @valid_actions)
  end

  defp validate_breakdown_structure(changeset) do
    case get_field(changeset, :breakdown) do
      nil ->
        changeset

      breakdown when is_map(breakdown) ->
        required_dimensions = ["technical_depth", "communication", "problem_solving", "culture_fit", "role_fit"]

        missing =
          required_dimensions
          |> Enum.reject(&Map.has_key?(breakdown, &1))

        if missing == [] do
          changeset
        else
          add_error(changeset, :breakdown, "missing required dimensions: #{Enum.join(missing, ", ")}")
        end

      _ ->
        add_error(changeset, :breakdown, "must be a JSON object")
    end
  end
end
