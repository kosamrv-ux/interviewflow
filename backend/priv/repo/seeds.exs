##############################################################################
# Development seed data for InterviewFlow
# Run with: mix run priv/repo/seeds.exs
# Or via Docker: make seed
##############################################################################

alias InterviewFlow.Repo
alias InterviewFlow.Accounts.{Company, User}
alias InterviewFlow.Jobs.Job
alias InterviewFlow.Candidates.{Candidate, Application}

IO.puts("Seeding development database...")

# ─── Company ─────────────────────────────────────────────────────────────────
{:ok, company} =
  %Company{}
  |> Company.registration_changeset(%{
    "name" => "TechCorp Inc.",
    "slug" => "techcorp",
    "domain" => "techcorp.example.com",
    "plan" => "growth",
    "seats_limit" => 25
  })
  |> Repo.insert(on_conflict: {:replace_all_except, [:id, :inserted_at]}, conflict_target: :slug, returning: true)

IO.puts("  ✓ Company: #{company.name} (#{company.id})")

# ─── Users ───────────────────────────────────────────────────────────────────
{:ok, admin} =
  %User{}
  |> User.registration_changeset(%{
    "company_id" => company.id,
    "email" => "admin@techcorp.example.com",
    "password" => "DevAdmin123!",
    "password_confirmation" => "DevAdmin123!",
    "full_name" => "Admin User"
  })
  |> Ecto.Changeset.put_change(:role, "admin")
  |> Ecto.Changeset.put_change(:confirmed_at, DateTime.utc_now() |> DateTime.truncate(:microsecond))
  |> Repo.insert(on_conflict: {:replace_all_except, [:id, :inserted_at]}, conflict_target: :email, returning: true)

IO.puts("  ✓ Admin:   #{admin.email} / DevAdmin123!")

{:ok, recruiter} =
  %User{}
  |> User.registration_changeset(%{
    "company_id" => company.id,
    "email" => "recruiter@techcorp.example.com",
    "password" => "DevRecruiter123!",
    "password_confirmation" => "DevRecruiter123!",
    "full_name" => "Sarah Recruiter"
  })
  |> Ecto.Changeset.put_change(:confirmed_at, DateTime.utc_now() |> DateTime.truncate(:microsecond))
  |> Repo.insert(on_conflict: {:replace_all_except, [:id, :inserted_at]}, conflict_target: :email, returning: true)

IO.puts("  ✓ Recruiter: #{recruiter.email} / DevRecruiter123!")

# ─── Jobs ────────────────────────────────────────────────────────────────────
jobs_data = [
  %{
    title: "Senior Backend Engineer (Elixir)",
    department: "Engineering",
    location: "Austin, TX",
    remote_policy: "hybrid",
    employment_type: "full_time",
    description: "Join our platform team to build the core API powering InterviewFlow. You'll work with Elixir, Phoenix, and PostgreSQL to handle thousands of concurrent video sessions.",
    requirements: "5+ years backend experience, 2+ years Elixir or Erlang, PostgreSQL, Redis, experience with WebRTC or real-time systems a plus.",
    salary_min: 15_000_000,
    salary_max: 22_000_000,
    status: "open"
  },
  %{
    title: "Frontend Engineer (React / TypeScript)",
    department: "Engineering",
    location: "Remote",
    remote_policy: "remote",
    employment_type: "full_time",
    description: "Build the recruiter dashboard and candidate interview experience. You'll own the WebRTC integration, Monaco Editor embedding, and real-time scorecard rendering.",
    requirements: "4+ years React experience, TypeScript proficiency, experience with WebSockets or WebRTC, TanStack Query.",
    salary_min: 13_000_000,
    salary_max: 19_000_000,
    status: "open"
  },
  %{
    title: "ML Engineer (Vertex AI)",
    department: "AI/ML",
    location: "San Francisco, CA",
    remote_policy: "hybrid",
    employment_type: "full_time",
    description: "Design and improve our AI candidate scoring pipeline using Vertex AI and Gemini. Own prompt engineering, evaluation frameworks, and fine-tuning experiments.",
    requirements: "3+ years ML engineering, Python, experience with LLMs and prompt engineering, GCP/Vertex AI preferred.",
    salary_min: 16_000_000,
    salary_max: 24_000_000,
    status: "draft"
  }
]

created_jobs =
  Enum.map(jobs_data, fn attrs ->
    {:ok, job} =
      %Job{}
      |> Job.changeset(Map.merge(attrs, %{company_id: company.id, created_by_id: recruiter.id}))
      |> Repo.insert(returning: true)

    IO.puts("  ✓ Job: #{job.title} (#{job.status})")
    job
  end)

[backend_job, frontend_job | _] = created_jobs

# ─── Candidates ──────────────────────────────────────────────────────────────
candidates_data = [
  %{email: "alex.chen@example.com", full_name: "Alex Chen", source: "linkedin",
    github_url: "https://github.com/alexchen", tags: ["elixir", "distributed-systems"]},
  %{email: "priya.sharma@example.com", full_name: "Priya Sharma", source: "referral",
    linkedin_url: "https://linkedin.com/in/priyasharma", tags: ["react", "typescript"]},
  %{email: "jordan.kim@example.com", full_name: "Jordan Kim", source: "careers_page",
    github_url: "https://github.com/jordankim", tags: ["elixir", "phoenix"]},
  %{email: "sofia.rodriguez@example.com", full_name: "Sofia Rodriguez", source: "linkedin",
    linkedin_url: "https://linkedin.com/in/sofiar", tags: ["react", "webrtc"]}
]

created_candidates =
  Enum.map(candidates_data, fn attrs ->
    {:ok, candidate} =
      %Candidate{}
      |> Candidate.changeset(Map.put(attrs, :company_id, company.id))
      |> Repo.insert(returning: true)

    IO.puts("  ✓ Candidate: #{candidate.full_name}")
    candidate
  end)

[alex, priya, jordan, sofia] = created_candidates

# ─── Applications ─────────────────────────────────────────────────────────────
applications_data = [
  {alex, backend_job, "interview"},
  {priya, frontend_job, "screen"},
  {jordan, backend_job, "applied"},
  {sofia, frontend_job, "interview"}
]

Enum.each(applications_data, fn {candidate, job, stage} ->
  {:ok, app} =
    %Application{}
    |> Application.submission_changeset(%{job_id: job.id, candidate_id: candidate.id})
    |> Ecto.Changeset.put_change(:pipeline_stage, stage)
    |> Ecto.Changeset.put_change(:assigned_to_id, recruiter.id)
    |> Repo.insert(returning: true)

  IO.puts("  ✓ Application: #{candidate.full_name} → #{job.title} (#{stage})")
  app
end)

IO.puts("\n✓ Seed complete!")
IO.puts("  Login as admin:     admin@techcorp.example.com / DevAdmin123!")
IO.puts("  Login as recruiter: recruiter@techcorp.example.com / DevRecruiter123!")
