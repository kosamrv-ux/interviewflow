defmodule InterviewFlow.Factory do
  @moduledoc """
  ExMachina factory for test data.
  Provides builder functions for all major domain entities.
  """

  use ExMachina.Ecto, repo: InterviewFlow.Repo

  alias InterviewFlow.Accounts.{Company, User}
  alias InterviewFlow.Jobs.Job
  alias InterviewFlow.Candidates.{Candidate, Application}

  def company_factory do
    name = Faker.Company.name()

    %Company{
      name: name,
      slug: Company.slugify(name) <> "-#{System.unique_integer([:positive])}",
      domain: Faker.Internet.domain_name(),
      plan: "starter",
      seats_limit: 10,
      settings: %{}
    }
  end

  def user_factory do
    %User{
      company: build(:company),
      email: Faker.Internet.email(),
      hashed_password: Bcrypt.hash_pwd_salt("TestPassword1!"),
      full_name: Faker.Person.name(),
      role: "recruiter",
      confirmed_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
    }
  end

  def admin_user_factory do
    struct!(user_factory(), role: "admin")
  end

  def job_factory do
    company = build(:company)

    %Job{
      company: company,
      created_by: build(:user, company: company),
      title: "#{Faker.Job.title()} Engineer",
      department: Faker.Job.field(),
      location: "#{Faker.Address.city()}, #{Faker.Address.state_abbr()}",
      remote_policy: "hybrid",
      employment_type: "full_time",
      description: Faker.Lorem.paragraphs(3) |> Enum.join("\n\n"),
      requirements: Faker.Lorem.paragraphs(2) |> Enum.join("\n\n"),
      salary_min: 10_000_000,
      salary_max: 20_000_000,
      salary_currency: "USD",
      pipeline_stages: ["applied", "screen", "interview", "offer", "hired"],
      scoring_rubric: %{
        "technical_depth" => %{"weight" => 0.35},
        "communication" => %{"weight" => 0.25},
        "problem_solving" => %{"weight" => 0.20},
        "culture_fit" => %{"weight" => 0.10},
        "role_fit" => %{"weight" => 0.10}
      },
      status: "open",
      published_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
    }
  end

  def draft_job_factory do
    struct!(job_factory(), status: "draft", published_at: nil)
  end

  def candidate_factory do
    company = build(:company)

    %Candidate{
      company: company,
      email: Faker.Internet.email(),
      email_encrypted: :crypto.hash(:sha256, "test@example.com"),
      full_name: Faker.Person.name(),
      phone: Faker.Phone.EnUs.phone(),
      linkedin_url: "https://linkedin.com/in/#{Faker.Internet.user_name()}",
      github_url: "https://github.com/#{Faker.Internet.user_name()}",
      source: "linkedin",
      tags: []
    }
  end

  def application_factory do
    job = build(:job)
    candidate = build(:candidate, company: job.company)

    %Application{
      job: job,
      candidate: candidate,
      pipeline_stage: "applied",
      status: "active",
      applied_at: DateTime.utc_now() |> DateTime.truncate(:microsecond),
      stage_changed_at: DateTime.utc_now() |> DateTime.truncate(:microsecond),
      source_details: %{}
    }
  end

  alias InterviewFlow.Interviews.{Interview, VideoSession}
  alias InterviewFlow.Scoring.AiScore
  alias InterviewFlow.Candidates.Invitation

  def interview_factory do
    %Interview{
      application: build(:application),
      title: "#{Enum.random(["Technical", "Phone Screen", "Onsite", "Panel"])} Interview",
      interview_type: Enum.random(["video", "phone", "technical", "panel"]),
      status: "scheduled",
      scheduled_at:
        DateTime.utc_now()
        |> DateTime.add(Enum.random(1..14) * 86_400, :second)
        |> DateTime.truncate(:microsecond),
      duration_minutes: Enum.random([30, 45, 60, 90]),
      notes: Faker.Lorem.sentence()
    }
  end

  def video_session_factory do
    %VideoSession{
      interview: build(:interview),
      status: "active",
      participant_count: 0,
      started_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
    }
  end

  def ai_score_factory do
    %AiScore{
      application: build(:application),
      composite_score: Enum.random(50..95) / 100,
      communication_score: Enum.random(50..95) / 100,
      technical_score: Enum.random(50..95) / 100,
      problem_solving_score: Enum.random(50..95) / 100,
      cultural_fit_score: Enum.random(50..95) / 100,
      summary: Faker.Lorem.sentence(12),
      strengths: Faker.Lorem.words(3),
      concerns: Faker.Lorem.words(2),
      recommendation: Enum.random(["strong_hire", "hire", "no_hire"]),
      model_version: "gemini-1.5-pro-002",
      scored_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
    }
  end

  def invitation_factory do
    %Invitation{
      company: build(:company),
      invited_by: build(:user),
      email: Faker.Internet.email(),
      role: "recruiter",
      token: :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false),
      expires_at:
        DateTime.utc_now()
        |> DateTime.add(7 * 86_400, :second)
        |> DateTime.truncate(:microsecond)
    }
  end
end
