defmodule InterviewFlow.Auth.TokenRefresh do
  @moduledoc """
  Handles JWT access token refresh using a valid refresh token.

  Enforces a rotation strategy: each refresh invalidates the old refresh
  token (adds its JTI to the blacklist) and issues a fresh token pair.
  This limits the blast radius if a refresh token is compromised.
  """

  alias InterviewFlow.Auth.{Guardian, TokenBlacklist}

  @doc """
  Exchanges a valid refresh token for a new access + refresh token pair.

  Returns `{:ok, token_map}` or `{:error, reason}`.
  """
  @spec exchange(String.t()) ::
          {:ok, %{access_token: String.t(), refresh_token: String.t(), expires_in: integer()}}
          | {:error, atom() | String.t()}
  def exchange(refresh_token) when is_binary(refresh_token) do
    with {:ok, claims} <- decode_and_verify(refresh_token),
         :ok <- assert_refresh_type(claims),
         :ok <- assert_not_blacklisted(claims),
         {:ok, user, _} <- Guardian.resource_from_token(refresh_token),
         :ok <- blacklist_old_token(claims),
         {:ok, token_pair} <- Guardian.issue_token_pair(user) do
      {:ok, token_pair}
    end
  end

  def exchange(_), do: {:error, :invalid_token}

  # ── Private helpers ──────────────────────────────────────────────────────

  defp decode_and_verify(token) do
    case Guardian.decode_and_verify(token) do
      {:ok, claims} -> {:ok, claims}
      {:error, reason} -> {:error, reason}
    end
  end

  defp assert_refresh_type(%{"typ" => "refresh"}), do: :ok
  defp assert_refresh_type(_), do: {:error, :not_refresh_token}

  defp assert_not_blacklisted(%{"jti" => jti}) do
    if TokenBlacklist.member?(jti),
      do: {:error, :token_revoked},
      else: :ok
  end

  defp assert_not_blacklisted(_), do: {:error, :missing_jti}

  defp blacklist_old_token(%{"jti" => jti, "exp" => exp}) do
    ttl = max(exp - System.system_time(:second), 0)
    TokenBlacklist.add(jti, ttl)
  end

  defp blacklist_old_token(_), do: {:error, :missing_claims}
end
