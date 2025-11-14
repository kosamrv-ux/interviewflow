defmodule InterviewFlow.AccountsTest do
  use InterviewFlow.DataCase, async: true

  alias InterviewFlow.Accounts
  alias InterviewFlow.Accounts.{Company, User}

  describe "register_company/2" do
    test "creates a company and admin user with valid attrs" do
      company_attrs = %{"name" => "Acme Corp", "slug" => "acme-corp"}
      user_attrs = %{
        "email" => "admin@acme.com",
        "password" => "SecurePass123!",
        "password_confirmation" => "SecurePass123!",
        "full_name" => "Jane Doe"
      }

      assert {:ok, %{company: company, user: user}} =
               Accounts.register_company(company_attrs, user_attrs)

      assert company.name == "Acme Corp"
      assert company.slug == "acme-corp"
      assert company.plan == "trial"

      assert user.email == "admin@acme.com"
      assert user.role == "admin"
      assert user.company_id == company.id
      assert user.hashed_password != "SecurePass123!"
    end

    test "returns error when slug is taken" do
      insert(:company, slug: "taken-slug")

      company_attrs = %{"name" => "Another Corp", "slug" => "taken-slug"}
      user_attrs = %{
        "email" => "other@corp.com",
        "password" => "SecurePass123!",
        "password_confirmation" => "SecurePass123!",
        "full_name" => "Bob Smith"
      }

      assert {:error, changeset} = Accounts.register_company(company_attrs, user_attrs)
      assert %{slug: ["has already been taken"]} = errors_on(changeset)
    end

    test "returns error when email is invalid" do
      company_attrs = %{"name" => "Valid Corp", "slug" => "valid-corp-#{System.unique_integer()}"}
      user_attrs = %{
        "email" => "not-an-email",
        "password" => "SecurePass123!",
        "password_confirmation" => "SecurePass123!",
        "full_name" => "Jane Doe"
      }

      assert {:error, changeset} = Accounts.register_company(company_attrs, user_attrs)
      assert %{email: [_]} = errors_on(changeset)
    end

    test "returns error when password is too short" do
      company_attrs = %{"name" => "Short Pass Corp", "slug" => "short-pass-#{System.unique_integer()}"}
      user_attrs = %{
        "email" => "admin@short.com",
        "password" => "Short1!",
        "password_confirmation" => "Short1!",
        "full_name" => "Jane Doe"
      }

      assert {:error, changeset} = Accounts.register_company(company_attrs, user_attrs)
      assert %{password: [_]} = errors_on(changeset)
    end
  end

  describe "authenticate_user/2" do
    test "returns user on correct credentials" do
      user = insert(:user, email: "auth@test.com", hashed_password: Bcrypt.hash_pwd_salt("GoodPassword99!"))

      assert {:ok, returned_user} = Accounts.authenticate_user("auth@test.com", "GoodPassword99!")
      assert returned_user.id == user.id
      assert returned_user.last_sign_in_at != nil
    end

    test "returns error on wrong password" do
      insert(:user, email: "wrong@test.com", hashed_password: Bcrypt.hash_pwd_salt("RealPass123!"))
      assert {:error, :invalid_credentials} = Accounts.authenticate_user("wrong@test.com", "WrongPass!")
    end

    test "returns error for non-existent email (timing safe)" do
      # Should call bcrypt even for missing users to prevent timing attacks
      assert {:error, :invalid_credentials} = Accounts.authenticate_user("nobody@nowhere.com", "AnyPass123!")
    end
  end

  describe "Company.slugify/1" do
    test "converts company name to URL-safe slug" do
      assert Company.slugify("Acme Corp") == "acme-corp"
      assert Company.slugify("My Company, LLC") == "my-company-llc"
      assert Company.slugify("Tech & Beyond") == "tech--beyond"
      assert Company.slugify("  Trim Me  ") == "trim-me"
    end
  end

  describe "has_role?/2" do
    test "returns true when user has the given role" do
      user = build(:user, role: "recruiter")
      assert Accounts.has_role?(user, "recruiter")
      assert Accounts.has_role?(user, ["admin", "recruiter"])
    end

    test "returns false when user does not have the role" do
      user = build(:user, role: "interviewer")
      refute Accounts.has_role?(user, "admin")
      refute Accounts.has_role?(user, ["admin", "recruiter"])
    end
  end
end
