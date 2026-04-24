defmodule InterviewFlow.ApiKeys do
  @moduledoc """
  Context for API key management.

  API keys are scoped to an organization and have an optional expiry.
  The raw key is only returned once at creation time; only the hashed
  value is stored (bcrypt). Prefix stored for display/lookup purposes.

  Key format: `if_live_<32 random hex chars>` (production)
               `if_test_<32 random hex chars>` (test environment)
  """

  import Ecto.Query, warn: false

  alias InterviewFlow.Repo
  alias InterviewFlow.ApiKeys.ApiKey

  @prefix if Mix.env() == :prod, do: "if_live_", else: "if_test_"

  @doc """
  Lists all active (non-revoked) API keys for an organization.
  The key_hash field is not returned; use this for display only.
  """
  def list_api_keys(org_id) do
    from(k in ApiKey,
      where: k.org_id == ^org_id and is_nil(k.revoked_at),
      select: %{
        id: k.id,
        name: k.name,
        key_prefix: k.key_prefix,
        scopes: k.scopes,
        last_used_at: k.last_used_at,
        expires_at: k.expires_at,
        inserted_at: k.inserted_at
      },
      order_by: [desc: k.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Creates a new API key and returns {:ok, {api_key, raw_key}}.
  The raw_key is only available at this point; store it safely.
  """
  def create_api_key(attrs) do
    raw_key = generate_raw_key()
    prefix = String.slice(raw_key, 0, String.length(@prefix) + 8)
    hashed = Bcrypt.hash_pwd_salt(raw_key)

    changeset =
      %ApiKey{}
      |> ApiKey.changeset(attrs)
      |> Ecto.Changeset.put_change(:key_prefix, prefix)
      |> Ecto.Changeset.put_change(:key_hash, hashed)

    case Repo.insert(changeset) do
      {:ok, api_key} -> {:ok, {api_key, raw_key}}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Rotates an API key: revokes the old one and creates a new key with
  the same name and scopes.
  """
  def rotate_api_key(%ApiKey{} = old_key, user_id) do
    Repo.transaction(fn ->
      {:ok, _} = revoke_api_key(old_key, user_id)

      case create_api_key(%{
        name: "#{old_key.name} (rotated)",
        scopes: old_key.scopes,
        org_id: old_key.org_id,
        created_by_id: user_id,
        expires_at: old_key.expires_at
      }) do
        {:ok, result} -> result
        {:error, cs} -> Repo.rollback(cs)
      end
    end)
  end

  @doc """
  Revokes an API key immediately.
  """
  def revoke_api_key(%ApiKey{} = api_key, revoked_by_user_id) do
    api_key
    |> Ecto.Changeset.change(%{revoked_at: DateTime.utc_now(), revoked_by: revoked_by_user_id})
    |> Repo.update()
  end

  @doc """
  Authenticates a raw API key. Returns {:ok, api_key} or :error.
  Updates last_used_at on success.
  """
  def authenticate(raw_key) do
    prefix = String.slice(raw_key, 0, String.length(@prefix) + 8)

    with %ApiKey{} = key <- find_by_prefix(prefix),
         true <- ApiKey.active?(key),
         true <- Bcrypt.verify_pass(raw_key, key.key_hash) do
      touch_last_used(key)
      {:ok, key}
    else
      _ -> :error
    end
  end

  defp find_by_prefix(prefix) do
    Repo.get_by(ApiKey, key_prefix: prefix)
  end

  defp touch_last_used(%ApiKey{id: id}) do
    from(k in ApiKey, where: k.id == ^id)
    |> Repo.update_all(set: [last_used_at: DateTime.utc_now()])
  end

  defp generate_raw_key do
    @prefix <> (:crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower))
  end
end
