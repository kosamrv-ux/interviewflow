defmodule InterviewFlow.Interviews.SchedulerTest do
  use InterviewFlow.DataCase, async: true

  alias InterviewFlow.Interviews.Scheduler
  alias InterviewFlow.Factory

  describe "schedule/1" do
    test "successfully schedules an interview in the future" do
      company = Factory.insert(:company)
      job = Factory.insert(:job, company_id: company.id)
      candidate = Factory.insert(:candidate, company_id: company.id)
      application = Factory.insert(:application, job_id: job.id, candidate_id: candidate.id)
      interviewer = Factory.insert(:user, company_id: company.id, role: "interviewer")

      attrs = %{
        application_id: application.id,
        interviewer_id: interviewer.id,
        title: "Technical Round 1",
        interview_type: "video",
        scheduled_at: future_datetime(days: 3),
        duration_minutes: 60
      }

      assert {:ok, interview} = Scheduler.schedule(attrs)
      assert interview.title == "Technical Round 1"
      assert interview.duration_minutes == 60
    end

    test "rejects scheduling in the past" do
      attrs = %{
        application_id: Ecto.UUID.generate(),
        interviewer_id: Ecto.UUID.generate(),
        title: "Past Interview",
        scheduled_at: ~U[2020-01-01 10:00:00Z],
        duration_minutes: 60
      }

      assert {:error, "interview must be scheduled in the future"} = Scheduler.schedule(attrs)
    end

    test "rejects duration shorter than minimum" do
      attrs = %{
        scheduled_at: future_datetime(days: 1),
        duration_minutes: 5
      }

      assert {:error, msg} = Scheduler.schedule(attrs)
      assert msg =~ "at least"
    end

    test "rejects duration longer than maximum" do
      attrs = %{
        scheduled_at: future_datetime(days: 1),
        duration_minutes: 300
      }

      assert {:error, msg} = Scheduler.schedule(attrs)
      assert msg =~ "must not exceed"
    end

    test "detects scheduling conflict with existing interview" do
      company = Factory.insert(:company)
      interviewer = Factory.insert(:user, company_id: company.id, role: "interviewer")
      job = Factory.insert(:job, company_id: company.id)

      app1 = Factory.insert(:application, job_id: job.id)
      app2 = Factory.insert(:application, job_id: job.id)

      slot = future_datetime(days: 2, hours: 10)

      # Schedule first interview
      {:ok, _} =
        Scheduler.schedule(%{
          application_id: app1.id,
          interviewer_id: interviewer.id,
          title: "First",
          interview_type: "video",
          scheduled_at: slot,
          duration_minutes: 60
        })

      # Try to schedule overlapping interview for same interviewer
      assert {:error, "scheduling conflict" <> _} =
               Scheduler.schedule(%{
                 application_id: app2.id,
                 interviewer_id: interviewer.id,
                 title: "Overlap",
                 interview_type: "video",
                 scheduled_at: DateTime.add(slot, 30 * 60, :second),
                 duration_minutes: 60
               })
    end
  end

  describe "reschedule/2" do
    test "successfully reschedules to a non-conflicting slot" do
      company = Factory.insert(:company)
      interviewer = Factory.insert(:user, company_id: company.id)
      app = Factory.insert(:application)

      {:ok, interview} =
        Scheduler.schedule(%{
          application_id: app.id,
          interviewer_id: interviewer.id,
          title: "Original",
          interview_type: "phone",
          scheduled_at: future_datetime(days: 5),
          duration_minutes: 45
        })

      new_slot = future_datetime(days: 7)
      assert {:ok, updated} = Scheduler.reschedule(interview, %{scheduled_at: new_slot})
      assert DateTime.compare(updated.scheduled_at, new_slot) == :eq
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────────

  defp future_datetime(days: d, hours: h) do
    DateTime.utc_now()
    |> DateTime.add(d * 86400 + h * 3600, :second)
    |> DateTime.truncate(:second)
  end

  defp future_datetime(days: d) do
    future_datetime(days: d, hours: 0)
  end
end
