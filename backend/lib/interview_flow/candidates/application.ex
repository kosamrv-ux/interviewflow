defmodule InterviewFlow.Candidates.Application do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @valid_statuses ~w(active rejected withdrawn hired)
  @valid_rejection_reasons ~w(
    underqualified overqualified failed_assessment culture_fit
    withdrew position_filled no_response other
  )

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "applications" do
    field :pipeline_stage, :string, default: "applied"
    field :rejection_reason, :string
    field :cover_letter, :string
    field :referral_name, :string
    field :source_details, :map, default: %{}
    field :composite_score, :decimal
    field :rank_within_job, :integer
    field :status, :string, default: "active"
    field :applied_at, :utc_datetime_usec
    field :stage_changed_at, :utc_datetime_usec

    belongs_to :job, InterviewFlow.Jobs.Job
    belongs_to :candidate, InterviewFlow.Candidates.Candidate
    belongs_to :assigned_to, InterviewFlow.Accounts.User, foreign_key: :assigned_to_id

    has_many :interviews, InterviewFlow.Interviews.Interview
    has_many :ai_scores, InterviewFlow.Scoring.AiScore

    timestamps(type: :utc_datetime_usec)
  end

  @doc "Changeset for public application submission (no auth required)."
  def submission_changeset(application, attrs) do
    application
    |> cast(attrs, [:job_id, :candidate_id, :cover_letter, :referral_name, :source_details])
    |> validate_required([:job_id, :candidate_id])
    |> validate_length(:cover_letter, max: 5000)
    |> unique_constraint([:job_id, :candidate_id], message: "you have already applied to this job")
    |> put_applied_at()
  end

  @doc "Changeset for recruiter-side application updates (notes, assignee)."
  def update_changeset(application, attrs) do
    application
    |> cast(attrs, [:assigned_to_id, :source_details])
  end

  @doc "Advances the application to the given pipeline stage."
  def advance_changeset(application, new_stage, job) do
    current_idx = Enum.find_index(job.pipeline_stages, &(&1 == application.pipeline_stage))
    new_idx = Enum.find_index(job.pipeline_stages, &(&1 == new_stage))

    cond do
      is_nil(new_idx) ->
        application
        |> change()
        |> add_error(:pipeline_stage, "#{new_stage} is not a valid stage for this job")

      application.status != "active" ->
        application
        |> change()
        |> add_error(:status, "cannot advance a #{application.status} application")

      new_idx <= current_idx ->
        application
        |> change()
        |> add_error(:pipeline_stage, "cannot move to a previous stage; use reject if needed")

      true ->
        now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
        change(application, pipeline_stage: new_stage, stage_changed_at: now)
    end
  end

  @doc "Changeset for rejecting an application."
  def reject_changeset(application, reason) do
    application
    |> cast(%{rejection_reason: reason, status: "rejected"}, [:rejection_reason, :status])
    |> validate_inclusion(:rejection_reason, @valid_rejection_reasons)
    |> validate_required([:rejection_reason])
  end

  @doc "Changeset for marking an application as hired."
  def hire_changeset(application) do
    if application.pipeline_stage != "offer" do
      application
      |> change()
      |> add_error(:pipeline_stage, "must be in 'offer' stage before marking as hired")
    else
      change(application, status: "hired", pipeline_stage: "hired")
    end
  end

  defp put_applied_at(changeset) do
    if get_field(changeset, :applied_at) do
      changeset
    else
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
      put_change(changeset, :applied_at, now)
    end
  end
end
