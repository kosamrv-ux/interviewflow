defmodule InterviewFlow.Jobs.InterviewTemplate do
  @moduledoc """
  Interview question templates scoped to a job and interview type.

  Templates enable recruiters to prepare structured question sets per job
  so that interviewers always have consistent, calibrated questions.

  Each template has:
  - A set of required and optional questions
  - A recommended time allocation per question
  - Skill tags for AI score weighting

  Templates are associated with a job and can be cloned across jobs.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_types ~w(phone_screen technical onsite panel values_fit)

  schema "interview_templates" do
    field :name, :string
    field :interview_type, :string
    field :description, :string
    field :estimated_duration_minutes, :integer, default: 60
    field :questions, {:array, :map}, default: []
    field :is_active, :boolean, default: true
    field :cloned_from_id, :binary_id

    belongs_to :job, InterviewFlow.Jobs.Job
    belongs_to :created_by, InterviewFlow.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  @doc "Changeset for creating or updating a template."
  def changeset(template, attrs) do
    template
    |> cast(attrs, [
      :name,
      :interview_type,
      :description,
      :estimated_duration_minutes,
      :questions,
      :is_active,
      :job_id,
      :created_by_id,
      :cloned_from_id
    ])
    |> validate_required([:name, :interview_type, :job_id, :created_by_id])
    |> validate_length(:name, min: 3, max: 255)
    |> validate_inclusion(:interview_type, @valid_types)
    |> validate_number(:estimated_duration_minutes, greater_than: 0, less_than_or_equal_to: 480)
    |> validate_questions()
  end

  @doc "Returns a deep copy of the template for use with a different job."
  def clone(template, new_job_id, actor_id) do
    %__MODULE__{}
    |> changeset(%{
      name: "#{template.name} (copy)",
      interview_type: template.interview_type,
      description: template.description,
      estimated_duration_minutes: template.estimated_duration_minutes,
      questions: template.questions,
      job_id: new_job_id,
      created_by_id: actor_id,
      cloned_from_id: template.id
    })
  end

  @doc "Returns the total estimated time for all required questions."
  def required_time_minutes(%__MODULE__{questions: questions}) do
    questions
    |> Enum.filter(& &1["required"])
    |> Enum.sum(& Map.get(&1, "time_minutes", 5))
  end

  @doc "Returns questions grouped by skill category."
  def questions_by_skill(%__MODULE__{questions: questions}) do
    Enum.group_by(questions, &Map.get(&1, "skill_tag", "general"))
  end

  # ── Private validators ────────────────────────────────────────────────────

  defp validate_questions(%Ecto.Changeset{} = changeset) do
    case get_change(changeset, :questions) do
      nil ->
        changeset

      questions ->
        if Enum.all?(questions, &valid_question?/1),
          do: changeset,
          else: add_error(changeset, :questions, "each question must have a text and type field")
    end
  end

  defp valid_question?(%{"text" => text, "type" => type})
       when is_binary(text) and is_binary(type) and text != "",
       do: true

  defp valid_question?(_), do: false
end
