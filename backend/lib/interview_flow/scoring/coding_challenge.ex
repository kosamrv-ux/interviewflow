defmodule InterviewFlow.Scoring.CodingChallenge do
  @moduledoc """
  Schema for in-session coding challenges attached to a video session.

  Stores the problem prompt, the candidate's live solution snapshot,
  the language they used, and optional test results returned by the
  AI scoring service after analysis.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  @supported_languages ~w(elixir javascript typescript python go rust java ruby sql)

  schema "coding_challenges" do
    belongs_to :video_session, InterviewFlow.Interviews.VideoSession
    belongs_to :application, InterviewFlow.Candidates.Application

    field :title, :string
    field :difficulty, :string
    field :language, :string
    field :problem_statement, :string

    # Snapshot of the candidate's code at session end — may be partial if
    # the session was terminated unexpectedly.
    field :candidate_code, :string

    # AI-populated after scoring. Stored as JSONB for flexible result schemas.
    field :test_results, :map, default: %{}

    # 0.0–10.0 coding dimension score rolled into the AiScore breakdown.
    field :code_quality_score, :decimal

    # Track approximate time the candidate spent on the challenge (seconds).
    field :time_spent_seconds, :integer

    field :submitted_at, :utc_datetime_usec

    timestamps()
  end

  @required ~w(video_session_id application_id title language problem_statement)a
  @optional ~w(difficulty candidate_code test_results code_quality_score time_spent_seconds submitted_at)a

  def changeset(challenge, attrs) do
    challenge
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:difficulty, ~w(easy medium hard), message: "must be easy, medium, or hard")
    |> validate_inclusion(:language, @supported_languages,
        message: "must be one of: #{Enum.join(@supported_languages, ", ")}")
    |> validate_number(:code_quality_score,
        greater_than_or_equal_to: 0,
        less_than_or_equal_to: 10)
    |> validate_number(:time_spent_seconds, greater_than_or_equal_to: 0)
    |> validate_length(:title, max: 200)
    |> validate_length(:candidate_code, max: 100_000)
    |> foreign_key_constraint(:video_session_id)
    |> foreign_key_constraint(:application_id)
  end

  @doc "Changeset for recording the candidate's code snapshot during a live session."
  def snapshot_changeset(challenge, code, language, time_spent_seconds) do
    challenge
    |> cast(%{candidate_code: code, language: language, time_spent_seconds: time_spent_seconds}, [
         :candidate_code,
         :language,
         :time_spent_seconds
       ])
    |> validate_inclusion(:language, @supported_languages)
    |> validate_length(:candidate_code, max: 100_000)
  end

  @doc "Changeset for writing back AI test results."
  def score_changeset(challenge, attrs) do
    challenge
    |> cast(attrs, [:test_results, :code_quality_score, :submitted_at])
    |> validate_required([:submitted_at])
    |> validate_number(:code_quality_score,
        greater_than_or_equal_to: 0,
        less_than_or_equal_to: 10)
    |> validate_test_results_schema()
  end

  defp validate_test_results_schema(changeset) do
    case get_change(changeset, :test_results) do
      nil ->
        changeset

      results when is_map(results) ->
        required_keys = ["passed", "failed", "total", "run_time_ms"]
        missing = Enum.reject(required_keys, &Map.has_key?(results, &1))

        if missing == [] do
          changeset
        else
          add_error(changeset, :test_results, "missing required keys: #{Enum.join(missing, ", ")}")
        end

      _ ->
        add_error(changeset, :test_results, "must be a map")
    end
  end
end
