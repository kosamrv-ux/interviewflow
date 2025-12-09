defmodule InterviewFlow.InterviewsTest do
  use InterviewFlow.DataCase, async: true

  alias InterviewFlow.Interviews
  alias InterviewFlow.Interviews.{Interview, VideoSession}

  describe "create_interview/3" do
    test "creates an interview with required fields" do
      company = insert(:company)
      user = insert(:user, company: company)
      job = insert(:job, company: company, created_by: user)
      candidate = insert(:candidate, company: company)
      application = insert(:application, job: job, candidate: candidate)

      scheduled_at = DateTime.add(DateTime.utc_now(), 86_400, :second)

      attrs = %{
        "application_id" => application.id,
        "scheduled_at" => DateTime.to_iso8601(scheduled_at),
        "interview_type" => "technical",
        "duration_minutes" => 60
      }

      assert {:ok, interview} = Interviews.create_interview(company.id, user, attrs)
      assert interview.application_id == application.id
      assert interview.interview_type == "technical"
      assert interview.duration_minutes == 60
      assert interview.scheduled_by_id == user.id
    end

    test "returns error when scheduled_at is in the past" do
      company = insert(:company)
      user = insert(:user, company: company)
      job = insert(:job, company: company, created_by: user)
      candidate = insert(:candidate, company: company)
      application = insert(:application, job: job, candidate: candidate)

      past = DateTime.add(DateTime.utc_now(), -3600, :second)

      attrs = %{
        "application_id" => application.id,
        "scheduled_at" => DateTime.to_iso8601(past),
        "interview_type" => "technical",
        "duration_minutes" => 60
      }

      assert {:error, changeset} = Interviews.create_interview(company.id, user, attrs)
      assert %{scheduled_at: [_]} = errors_on(changeset)
    end

    test "returns error for invalid interview_type" do
      company = insert(:company)
      user = insert(:user, company: company)
      job = insert(:job, company: company, created_by: user)
      candidate = insert(:candidate, company: company)
      application = insert(:application, job: job, candidate: candidate)

      scheduled_at = DateTime.add(DateTime.utc_now(), 86_400, :second)

      attrs = %{
        "application_id" => application.id,
        "scheduled_at" => DateTime.to_iso8601(scheduled_at),
        "interview_type" => "freestyle",
        "duration_minutes" => 30
      }

      assert {:error, changeset} = Interviews.create_interview(company.id, user, attrs)
      assert %{interview_type: [_]} = errors_on(changeset)
    end
  end

  describe "list_upcoming/2" do
    test "returns interviews scheduled in the next 7 days" do
      company = insert(:company)
      user = insert(:user, company: company)
      job = insert(:job, company: company, created_by: user)
      candidate = insert(:candidate, company: company)
      application = insert(:application, job: job, candidate: candidate)

      now = DateTime.utc_now()
      soon = DateTime.add(now, 2 * 86_400, :second)
      far = DateTime.add(now, 10 * 86_400, :second)

      insert(:interview, application: application, scheduled_by: user,
             scheduled_at: soon, status: "scheduled")
      insert(:interview, application: application, scheduled_by: user,
             scheduled_at: far, status: "scheduled")

      results = Interviews.list_upcoming(company.id, [])
      assert length(results) == 1
      assert List.first(results).scheduled_at == soon
    end

    test "excludes cancelled interviews" do
      company = insert(:company)
      user = insert(:user, company: company)
      job = insert(:job, company: company, created_by: user)
      candidate = insert(:candidate, company: company)
      application = insert(:application, job: job, candidate: candidate)

      soon = DateTime.add(DateTime.utc_now(), 86_400, :second)

      insert(:interview, application: application, scheduled_by: user,
             scheduled_at: soon, status: "cancelled")

      results = Interviews.list_upcoming(company.id, [])
      assert results == []
    end
  end

  describe "create_session/1" do
    test "creates a video session for an interview" do
      company = insert(:company)
      user = insert(:user, company: company)
      job = insert(:job, company: company, created_by: user)
      candidate = insert(:candidate, company: company)
      application = insert(:application, job: job, candidate: candidate)
      interview = insert(:interview, application: application, scheduled_by: user)

      assert {:ok, session} = Interviews.create_session(interview.id)
      assert session.interview_id == interview.id
      assert session.status == :pending
      assert is_binary(session.session_token)
      assert String.length(session.session_token) > 20
    end
  end

  describe "end_session/2" do
    test "marks session as ended and computes duration" do
      company = insert(:company)
      user = insert(:user, company: company)
      job = insert(:job, company: company, created_by: user)
      candidate = insert(:candidate, company: company)
      application = insert(:application, job: job, candidate: candidate)
      interview = insert(:interview, application: application, scheduled_by: user)

      activated_at = DateTime.add(DateTime.utc_now(), -1800, :second)

      session = insert(:video_session,
        interview: interview,
        application: application,
        status: :active,
        activated_at: activated_at
      )

      assert {:ok, ended} = Interviews.end_session(session.id, user)
      assert ended.status == :ended
      assert ended.duration_seconds >= 1799
      assert ended.ended_at != nil
    end

    test "returns error when session is already ended" do
      company = insert(:company)
      user = insert(:user, company: company)
      job = insert(:job, company: company, created_by: user)
      candidate = insert(:candidate, company: company)
      application = insert(:application, job: job, candidate: candidate)
      interview = insert(:interview, application: application, scheduled_by: user)

      session = insert(:video_session,
        interview: interview,
        application: application,
        status: :ended
      )

      assert {:error, :already_ended} = Interviews.end_session(session.id, user)
    end
  end
end
