defmodule InterviewFlow.Auth.TokenBlacklist do
  @moduledoc """
  Redis-backed token blacklist for JWT revocation.

  When a user logs out or an admin revokes access, the token JTI (JWT ID)
  is stored in Redis with a TTL matching the token's remaining lifetime.
  The `SetCurrentUser` plug checks this list on every authenticated request.
  """

  @prefix "token_blacklist:"

  @doc "Adds a token JTI to the blacklist with the given TTL in seconds."
  def add(jti, ttl_seconds) when is_binary(jti) and is_integer(ttl_seconds) do
    key = key(jti)

    case Redix.command(:redix, ["SET", key, "1", "EX", ttl_seconds]) do
      {:ok, "OK"} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Returns true if the given JTI is blacklisted."
  def member?(jti) when is_binary(jti) do
    case Redix.command(:redix, ["EXISTS", key(jti)]) do
      {:ok, 1} -> true
      {:ok, 0} -> false
      {:error, _} -> false
    end
  end

  @doc "Removes a JTI from the blacklist (e.g., after TTL cleanup tests)."
  def remove(jti) when is_binary(jti) do
    Redix.command(:redix, ["DEL", key(jti)])
    :ok
  end

  defp key(jti), do: @prefix <> jti
end
