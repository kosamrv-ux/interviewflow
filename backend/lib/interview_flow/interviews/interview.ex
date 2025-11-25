defmodule InterviewFlow.Interviews.Interview do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @valid_statuses ~w(scheduled in_progress completed cancelled no_show)
  @valid_types ~w(video phone onsite technical panel)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "interviews" do
    field :title, :string
    field :interview_type, :string, default: "video"
    field :scheduled_at, :utc_datetime_usec
    field :duration_minutes, :integer, default: 60
    field :timezone, :string, default: "UTC"
    field :calendar_event_id, :string
    field :meeting_link, :string
    field :instructions, :string
    field :status, :string, default: "scheduled"
    field :cancelled_reason, :string
    field :completed_at, :utc_datetime_usec

    belongs_to :application, InterviewFlow.Candidates.Application
    belongs_to :scheduled_by, InterviewFlow.Accounts.User, foreign_key: :scheduled_by_id

    has_many :video_sessions, InterviewFlow.Interviews.VideoSession

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(interview, attrs) do
    interview
    |> cast(attrs, [
      :application_id, :scheduled_by_id, :title, :interview_type,
      :scheduled_at, :duration_minutes, :timezone, :calendar_event_id,
      :meeting_link, :instructions, :status
    ])
    |> validate_required([:application_id, :scheduled_by_id, :title, :scheduled_at])
    |> validate_length(:title, min: 3, max: 255)
    |> validate_inclusion(:interview_type, @valid_types)
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_number(:duration_minutes, greater_than: 0, less_than_or_equal_to: 480)
    |> validate_future_date(:scheduled_at)
  end

  def cancel_changeset(interview, reason) do
    interview
    |> cast(%{cancelled_reason: reason, status: "cancelled"}, [:cancelled_reason, :status])
    |> validate_required([:cancelled_reason])
    |> validate_length(:cancelled_reason, min: 5, max: 500)
  end

  defp validate_future_date(changeset, field) do
    case get_change(changeset, field) do
      nil ->
        changeset

      date ->
        if DateTime.compare(date, DateTime.utc_now()) == :gt do
          changeset
        else
          add_error(changeset, field, "must be scheduled in the future")
        end
    end
  end
end
