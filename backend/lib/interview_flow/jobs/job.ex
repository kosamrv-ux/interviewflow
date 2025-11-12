defmodule InterviewFlow.Jobs.Job do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @valid_statuses ~w(draft open paused closed archived)
  @valid_remote_policies ~w(onsite hybrid remote)
  @valid_employment_types ~w(full_time part_time contract internship)

  @default_pipeline_stages ["applied", "screen", "interview", "offer", "hired"]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "jobs" do
    field :title, :string
    field :department, :string
    field :location, :string
    field :remote_policy, :string, default: "hybrid"
    field :employment_type, :string, default: "full_time"
    field :description, :string
    field :requirements, :string
    field :salary_min, :integer
    field :salary_max, :integer
    field :salary_currency, :string, default: "USD"
    field :pipeline_stages, {:array, :string}, default: @default_pipeline_stages
    field :scoring_rubric, :map, default: %{}
    field :status, :string, default: "draft"
    field :published_at, :utc_datetime_usec
    field :closed_at, :utc_datetime_usec
    field :deleted_at, :utc_datetime_usec

    belongs_to :company, InterviewFlow.Accounts.Company
    belongs_to :created_by, InterviewFlow.Accounts.User, foreign_key: :created_by_id
    has_many :applications, InterviewFlow.Candidates.Application

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(job, attrs) do
    job
    |> cast(attrs, [
      :title, :department, :location, :remote_policy, :employment_type,
      :description, :requirements, :salary_min, :salary_max, :salary_currency,
      :pipeline_stages, :scoring_rubric, :status, :company_id, :created_by_id
    ])
    |> validate_required([:title, :company_id, :created_by_id])
    |> validate_length(:title, min: 3, max: 255)
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_inclusion(:remote_policy, @valid_remote_policies)
    |> validate_inclusion(:employment_type, @valid_employment_types)
    |> validate_salary()
    |> validate_pipeline_stages()
  end

  def publish_changeset(job) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    job
    |> change(status: "open", published_at: now)
    |> validate_inclusion(:status, @valid_statuses)
  end

  def close_changeset(job) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    change(job, status: "closed", closed_at: now)
  end

  defp validate_salary(changeset) do
    changeset
    |> validate_number(:salary_min, greater_than: 0)
    |> validate_number(:salary_max, greater_than: 0)
    |> validate_salary_range()
  end

  defp validate_salary_range(changeset) do
    min = get_field(changeset, :salary_min)
    max = get_field(changeset, :salary_max)

    if min && max && min >= max do
      add_error(changeset, :salary_max, "must be greater than salary_min")
    else
      changeset
    end
  end

  defp validate_pipeline_stages(changeset) do
    stages = get_field(changeset, :pipeline_stages) || []

    cond do
      length(stages) < 2 ->
        add_error(changeset, :pipeline_stages, "must have at least 2 stages")

      "applied" not in stages ->
        add_error(changeset, :pipeline_stages, "must include 'applied' as the first stage")

      hd(stages) != "applied" ->
        add_error(changeset, :pipeline_stages, "'applied' must be the first stage")

      true ->
        changeset
    end
  end
end
