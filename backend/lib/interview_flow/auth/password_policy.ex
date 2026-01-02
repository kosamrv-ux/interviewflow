defmodule InterviewFlow.Auth.PasswordPolicy do
  @moduledoc """
  Enforces enterprise password policy rules for InterviewFlow users.

  Checks are intentionally kept as pure functions so they can be used
  from changesets, API controllers, and background jobs alike.
  """

  @min_length 12
  @max_length 72
  @common_passwords ~w(
    password123 Password123 Welcome1234 Letmein12! Qwerty12345
    Iloveyou123 Admin12345 Summer2024! Winter2025!
  )

  @doc """
  Validates a candidate password against the policy.

  Returns `:ok` or `{:error, [String.t()]}` with a list of violation messages.
  """
  @spec validate(String.t()) :: :ok | {:error, [String.t()]}
  def validate(password) when is_binary(password) do
    errors =
      []
      |> check_length(password)
      |> check_uppercase(password)
      |> check_lowercase(password)
      |> check_digit(password)
      |> check_special(password)
      |> check_common(password)

    if errors == [], do: :ok, else: {:error, Enum.reverse(errors)}
  end

  def validate(_), do: {:error, ["password must be a string"]}

  @doc "Returns a human-readable summary of the password policy requirements."
  def requirements do
    [
      "At least #{@min_length} characters",
      "At most #{@max_length} characters",
      "At least one uppercase letter (A–Z)",
      "At least one lowercase letter (a–z)",
      "At least one digit (0–9)",
      "At least one special character (!@#$%^&*...)",
      "Must not be a commonly used password"
    ]
  end

  # ── Private helpers ──────────────────────────────────────────────────────

  defp check_length(errors, pwd) do
    len = String.length(pwd)

    cond do
      len < @min_length -> ["must be at least #{@min_length} characters" | errors]
      len > @max_length -> ["must be at most #{@max_length} characters" | errors]
      true -> errors
    end
  end

  defp check_uppercase(errors, pwd) do
    if String.match?(pwd, ~r/[A-Z]/),
      do: errors,
      else: ["must contain at least one uppercase letter" | errors]
  end

  defp check_lowercase(errors, pwd) do
    if String.match?(pwd, ~r/[a-z]/),
      do: errors,
      else: ["must contain at least one lowercase letter" | errors]
  end

  defp check_digit(errors, pwd) do
    if String.match?(pwd, ~r/[0-9]/),
      do: errors,
      else: ["must contain at least one digit" | errors]
  end

  defp check_special(errors, pwd) do
    if String.match?(pwd, ~r/[!@#$%^&*()\-_=+\[\]{};:'",.<>?\/\\|`~]/),
      do: errors,
      else: ["must contain at least one special character" | errors]
  end

  defp check_common(errors, pwd) do
    if pwd in @common_passwords,
      do: ["must not be a commonly used password" | errors],
      else: errors
  end
end
