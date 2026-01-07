defmodule InterviewFlow.Auth.PasswordPolicyTest do
  use ExUnit.Case, async: true

  alias InterviewFlow.Auth.PasswordPolicy

  describe "validate/1" do
    test "accepts a strong password" do
      assert :ok = PasswordPolicy.validate("S3cur3P@ssw0rd!")
    end

    test "rejects password shorter than 12 characters" do
      assert {:error, errors} = PasswordPolicy.validate("Short1!")
      assert Enum.any?(errors, &String.contains?(&1, "at least 12"))
    end

    test "rejects password missing uppercase letter" do
      assert {:error, errors} = PasswordPolicy.validate("alllowercase1!")
      assert Enum.any?(errors, &String.contains?(&1, "uppercase"))
    end

    test "rejects password missing lowercase letter" do
      assert {:error, errors} = PasswordPolicy.validate("ALLUPPERCASE1!")
      assert Enum.any?(errors, &String.contains?(&1, "lowercase"))
    end

    test "rejects password missing a digit" do
      assert {:error, errors} = PasswordPolicy.validate("NoDigitsHere!")
      assert Enum.any?(errors, &String.contains?(&1, "digit"))
    end

    test "rejects password missing a special character" do
      assert {:error, errors} = PasswordPolicy.validate("NoSpecialChar12")
      assert Enum.any?(errors, &String.contains?(&1, "special character"))
    end

    test "rejects a commonly used password" do
      assert {:error, errors} = PasswordPolicy.validate("Password123")
      assert Enum.any?(errors, &String.contains?(&1, "commonly used"))
    end

    test "returns multiple violations in a single call" do
      assert {:error, errors} = PasswordPolicy.validate("short")
      assert length(errors) >= 3
    end

    test "returns error for non-binary input" do
      assert {:error, ["password must be a string"]} = PasswordPolicy.validate(nil)
      assert {:error, ["password must be a string"]} = PasswordPolicy.validate(12345)
    end
  end

  describe "requirements/0" do
    test "returns a non-empty list of strings" do
      reqs = PasswordPolicy.requirements()
      assert is_list(reqs)
      assert length(reqs) > 0
      assert Enum.all?(reqs, &is_binary/1)
    end
  end
end
