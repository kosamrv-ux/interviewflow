defmodule InterviewFlowWeb.Plugs.RequirePermissionTest do
  use ExUnit.Case, async: true

  alias InterviewFlowWeb.Plugs.RequirePermission

  describe "permitted?/3" do
    test "admin is permitted for any resource and action" do
      assert RequirePermission.permitted?("admin", :jobs, :publish)
      assert RequirePermission.permitted?("admin", :users, :delete)
      assert RequirePermission.permitted?("admin", :ai_scores, :override)
    end

    test "recruiter can read and write jobs" do
      assert RequirePermission.permitted?("recruiter", :jobs, :read)
      assert RequirePermission.permitted?("recruiter", :jobs, :write)
      assert RequirePermission.permitted?("recruiter", :jobs, :publish)
    end

    test "recruiter cannot manage users" do
      refute RequirePermission.permitted?("recruiter", :users, :write)
      refute RequirePermission.permitted?("recruiter", :users, :delete)
    end

    test "interviewer can read and write interviews" do
      assert RequirePermission.permitted?("interviewer", :interviews, :read)
      assert RequirePermission.permitted?("interviewer", :interviews, :write)
    end

    test "interviewer cannot publish jobs or override scores" do
      refute RequirePermission.permitted?("interviewer", :jobs, :publish)
      refute RequirePermission.permitted?("interviewer", :ai_scores, :override)
    end

    test "stakeholder has read-only access to all resources" do
      for resource <- [:jobs, :candidates, :applications, :interviews, :ai_scores] do
        assert RequirePermission.permitted?("stakeholder", resource, :read)
        refute RequirePermission.permitted?("stakeholder", resource, :write)
      end
    end

    test "unknown role is denied" do
      refute RequirePermission.permitted?("hacker", :jobs, :read)
    end
  end
end
