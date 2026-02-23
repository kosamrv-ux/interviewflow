defmodule InterviewFlow.Accounts.InvitationServiceTest do
  use InterviewFlow.DataCase, async: true

  alias InterviewFlow.Accounts.InvitationService
  alias InterviewFlow.Factory

  setup do
    company = Factory.insert(:company)
    admin = Factory.insert(:user, company_id: company.id, role: "admin")
    %{company: company, admin: admin}
  end

  describe "invite/2" do
    test "creates an invitation for a new email address", %{company: company, admin: admin} do
      attrs = %{email: "newperson@example.com", role: "recruiter", company_id: company.id}
      assert {:ok, invitation} = InvitationService.invite(attrs, admin)
      assert invitation.email == "newperson@example.com"
      assert invitation.role == "recruiter"
      assert invitation.token != nil
    end

    test "rejects invitation if user already exists in company", %{company: company, admin: admin} do
      existing = Factory.insert(:user, company_id: company.id, email: "existing@example.com")

      attrs = %{email: existing.email, role: "recruiter", company_id: company.id}
      assert {:error, msg} = InvitationService.invite(attrs, admin)
      assert msg =~ "already exists"
    end

    test "rejects invitation when pending limit is reached", %{company: company, admin: admin} do
      # Insert 20 pending invitations
      for i <- 1..20 do
        Factory.insert(:invitation,
          company_id: company.id,
          email: "pending#{i}@example.com",
          accepted_at: nil
        )
      end

      attrs = %{email: "newperson@example.com", role: "recruiter", company_id: company.id}
      assert {:error, msg} = InvitationService.invite(attrs, admin)
      assert msg =~ "limit"
    end
  end

  describe "accept/2" do
    test "creates a user from a valid invitation token", %{company: company} do
      invitation = Factory.insert(:invitation,
        company_id: company.id,
        email: "invitee@example.com",
        role: "interviewer",
        accepted_at: nil
      )

      user_attrs = %{
        full_name: "New Interviewer",
        password: "ValidP@ssword123!",
        password_confirmation: "ValidP@ssword123!"
      }

      assert {:ok, user} = InvitationService.accept(invitation.token, user_attrs)
      assert user.email == "invitee@example.com"
      assert user.role == "interviewer"
    end

    test "rejects an expired token", %{company: company} do
      past = DateTime.add(DateTime.utc_now(), -8 * 86_400, :second)
      invitation = Factory.insert(:invitation,
        company_id: company.id,
        expires_at: past,
        accepted_at: nil
      )

      assert {:error, :invalid_or_expired_token} =
               InvitationService.accept(invitation.token, %{full_name: "Test"})
    end

    test "rejects an already-accepted token", %{company: company} do
      invitation = Factory.insert(:invitation,
        company_id: company.id,
        accepted_at: DateTime.utc_now()
      )

      assert {:error, :invalid_or_expired_token} =
               InvitationService.accept(invitation.token, %{full_name: "Test"})
    end
  end

  describe "revoke/2" do
    test "admin can revoke a pending invitation", %{company: company, admin: admin} do
      invitation = Factory.insert(:invitation, company_id: company.id)
      assert :ok = InvitationService.revoke(invitation.id, admin)
    end

    test "non-admin cannot revoke an invitation", %{company: company} do
      recruiter = Factory.insert(:user, company_id: company.id, role: "recruiter")
      invitation = Factory.insert(:invitation, company_id: company.id)
      assert {:error, :forbidden} = InvitationService.revoke(invitation.id, recruiter)
    end

    test "returns error for non-existent invitation", %{admin: admin} do
      assert {:error, :not_found} = InvitationService.revoke(Ecto.UUID.generate(), admin)
    end
  end
end
