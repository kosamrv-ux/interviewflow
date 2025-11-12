defmodule InterviewFlow.Auth.Guardian do
  use Guardian, otp_app: :interview_flow

  alias InterviewFlow.Accounts

  @impl true
  def subject_for_token(%{id: id}, _claims) do
    {:ok, to_string(id)}
  end

  def subject_for_token(_, _) do
    {:error, :invalid_resource}
  end

  @impl true
  def resource_from_claims(%{"sub" => id, "company_id" => company_id}) do
    case Accounts.get_user(company_id, id) do
      nil -> {:error, :resource_not_found}
      user -> {:ok, user}
    end
  end

  def resource_from_claims(_), do: {:error, :invalid_claims}

  @impl true
  def build_claims(claims, resource, _opts) do
    claims =
      claims
      |> Map.put("company_id", resource.company_id)
      |> Map.put("role", resource.role)

    {:ok, claims}
  end

  @doc """
  Issues a JWT token pair for the given user.
  Returns `{:ok, %{access_token: token, refresh_token: token, expires_in: seconds}}`.
  """
  def issue_token_pair(user) do
    with {:ok, access_token, access_claims} <- encode_and_sign(user, %{}, token_type: "access"),
         {:ok, refresh_token, _} <-
           encode_and_sign(user, %{}, token_type: "refresh", ttl: {7, :days}) do
      expires_in =
        access_claims["exp"] - access_claims["iat"]

      {:ok,
       %{
         access_token: access_token,
         refresh_token: refresh_token,
         expires_in: expires_in,
         token_type: "Bearer"
       }}
    end
  end

  @doc "Revokes a token by adding it to the deny list (Guardian revocation)."
  def revoke_token(token) do
    revoke(token)
  end
end
