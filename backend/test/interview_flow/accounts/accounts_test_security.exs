defmodule InterviewFlow.Accounts.AccountsSecurityTest do
  @moduledoc """
  Security-focused tests for the Accounts context, specifically the
  brute-force protection changes added in March 2026.
  """

  use InterviewFlow.DataCase, async: true

  alias InterviewFlow.Accounts

  describe "authenticate_user/2 — brute force protection" do
    setup do
      {:ok, %{company: company, user: user}} =
        Accounts.register_company(
          %{"name" => "Test Co", "slug" => "test-co-#{System.unique_integer()}"},
          %{
            "email"                 => "secure-test-#{System.unique_integer()}@example.com",
            "password"              => "SecurePass123!",
            "password_confirmation" => "SecurePass123!",
            "full_name"             => "Security Tester"
          }
        )

      %{user: user}
    end

    test "returns {:ok, user} on correct credentials", %{user: user} do
      assert {:ok, returned_user} = Accounts.authenticate_user(user.email, "SecurePass123!")
      assert returned_user.id == user.id
    end

    test "returns {:error, :invalid_credentials} on wrong password", %{user: user} do
      assert {:error, :invalid_credentials} = Accounts.authenticate_user(user.email, "WrongPass!")
    end

    test "returns {:error, :invalid_credentials} for unknown email" do
      # Must not raise and must not reveal user existence via timing
      assert {:error, :invalid_credentials} =
        Accounts.authenticate_user("nonexistent@example.com", "SomePass123!")
    end

    test "increments failed_login_count on each failure", %{user: user} do
      Accounts.authenticate_user(user.email, "wrong1")
      Accounts.authenticate_user(user.email, "wrong2")

      updated = InterviewFlow.Repo.get!(InterviewFlow.Accounts.User, user.id)
      assert updated.failed_login_count >= 2
    end

    test "locks account after 5 consecutive failures", %{user: user} do
      for _ <- 1..5 do
        Accounts.authenticate_user(user.email, "wrong-password")
      end

      updated = InterviewFlow.Repo.get!(InterviewFlow.Accounts.User, user.id)
      assert not is_nil(updated.locked_until)
      assert DateTime.compare(updated.locked_until, DateTime.utc_now()) == :gt

      # Now correct password should return locked error
      assert {:error, {:account_locked, _}} =
        Accounts.authenticate_user(user.email, "SecurePass123!")
    end

    test "successful login resets failed_login_count", %{user: user} do
      # Fail twice first
      Accounts.authenticate_user(user.email, "wrong")
      Accounts.authenticate_user(user.email, "wrong")

      # Then succeed
      assert {:ok, _} = Accounts.authenticate_user(user.email, "SecurePass123!")

      updated = InterviewFlow.Repo.get!(InterviewFlow.Accounts.User, user.id)
      assert updated.failed_login_count == 0
    end
  end
end
