defmodule InterviewFlow.Interviews.VideoSession do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @valid_statuses ~w(waiting active ended failed)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "video_sessions" do
    field :session_token, :string
    field :status, :string, default: "waiting"
    field :started_at, :utc_datetime_usec
    field :ended_at, :utc_datetime_usec
    field :duration_seconds, :integer
    field :recording_url, :string
    field :transcript_url, :string
    field :participant_count, :integer, default: 0
    field :metadata, :map, default: %{}

    belongs_to :interview, InterviewFlow.Interviews.Interview
    has_many :ai_scores, InterviewFlow.Scoring.AiScore

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(session, attrs) do
    session
    |> cast(attrs, [:interview_id, :metadata])
    |> validate_required([:interview_id])
    |> put_change(:session_token, generate_session_token())
    |> put_change(:status, "waiting")
  end

  def activate_changeset(session) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    session
    |> change(status: "active", started_at: now)
    |> validate_inclusion(:status, @valid_statuses)
  end

  def end_changeset(session, attrs \\ %{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    duration =
      if session.started_at do
        DateTime.diff(now, session.started_at, :second)
      end

    session
    |> cast(attrs, [:recording_url, :transcript_url, :participant_count])
    |> change(status: "ended", ended_at: now, duration_seconds: duration)
  end

  defp generate_session_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end
end
