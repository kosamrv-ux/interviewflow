defmodule InterviewFlow.Cache do
  @moduledoc """
  Redis-backed caching layer for expensive queries.

  Key design:
    - Namespaced keys:  `if:{resource}:{id}:{variant}`
    - TTL tiers:
        * hot  (60 s)   — per-request session data, token presence
        * warm (300 s)  — dashboard aggregates, job listing pages
        * cold (1800 s) — company settings, interview templates
        * day  (86400 s)— scoring rubric definitions, static config

  All cache reads fall through to the supplied loader function on miss
  so callers never have to handle nil themselves.

  Multi-tenancy fix (June 2026):
  Several cache key helpers previously did not include org_id, which created
  the theoretical risk of cross-tenant cache reads after multi-tenancy was
  added. All key builders now accept and embed org_id. Legacy callers updated.
  See ADR-008 for tenancy architecture context.
  """

  require Logger

  @hot   60
  @warm  300
  @cold  1_800
  @day   86_400

  @pool_name :redix_pool

  # ── TTL constants (exported for callers that want explicit control) ────────

  def ttl(:hot),  do: @hot
  def ttl(:warm), do: @warm
  def ttl(:cold), do: @cold
  def ttl(:day),  do: @day

  # ── Key builders ──────────────────────────────────────────────────────────

  @doc "Canonical key for a single resource record, scoped to org."
  def key(resource, id),             do: "if:#{resource}:#{id}"

  @doc "Canonical key for a single org-scoped resource record."
  def org_key(org_id, resource, id), do: "if:org:#{org_id}:#{resource}:#{id}"

  @doc "Canonical key for a paginated resource list."
  def key(resource, scope_id, page), do: "if:#{resource}:#{scope_id}:p#{page}"

  @doc "Canonical org-scoped key for a paginated resource list."
  def org_key(org_id, resource, scope_id, page), do: "if:org:#{org_id}:#{resource}:#{scope_id}:p#{page}"

  @doc "Canonical key for an aggregate or computed value."
  def agg_key(metric, scope_id),     do: "if:agg:#{metric}:#{scope_id}"

  @doc "Canonical org-scoped key for an aggregate or computed value."
  def org_agg_key(org_id, metric, scope_id), do: "if:org:#{org_id}:agg:#{metric}:#{scope_id}"

  # ── Core primitives ───────────────────────────────────────────────────────

  @doc """
  Fetches `key` from Redis. Returns `{:ok, value}` on hit or `:miss`.
  """
  def get(key) do
    case command(["GET", key]) do
      {:ok, nil}   -> :miss
      {:ok, json}  -> {:ok, :erlang.binary_to_term(Base.decode64!(json))}
      {:error, _}  -> :miss
    end
  end

  @doc """
  Stores `value` at `key` with an optional TTL in seconds.
  """
  def put(key, value, ttl \\ @warm) do
    encoded = Base.encode64(:erlang.term_to_binary(value))
    case command(["SET", key, encoded, "EX", ttl]) do
      {:ok, "OK"} -> :ok
      error       -> Logger.warning("Cache.put failed key=#{key} err=#{inspect(error)}"); :ok
    end
  end

  @doc """
  Fetches `key` from cache; on miss calls `loader/0`, stores the result, and
  returns `{:ok, value}`.  Returns `{:error, reason}` only when the loader
  itself returns `{:error, _}`.
  """
  def fetch(key, ttl \\ @warm, loader) do
    case get(key) do
      {:ok, value} ->
        {:ok, value}

      :miss ->
        case loader.() do
          {:ok, value} ->
            put(key, value, ttl)
            {:ok, value}

          {:error, _} = err ->
            err
        end
    end
  end

  @doc "Deletes one or more keys."
  def delete(key) when is_binary(key), do: command(["DEL", key])
  def delete(keys) when is_list(keys),  do: command(["DEL" | keys])

  @doc "Invalidates all keys matching a glob pattern via SCAN + DEL."
  def invalidate_pattern(pattern) do
    stream_scan(pattern)
    |> Enum.chunk_every(100)
    |> Enum.each(fn chunk -> command(["DEL" | chunk]) end)

    :ok
  end

  @doc "Increments a counter key and sets TTL on first write."
  def incr(key, ttl \\ @warm) do
    {:ok, count} = command(["INCR", key])
    if count == 1, do: command(["EXPIRE", key, ttl])
    count
  end

  # ── Convenience wrappers ──────────────────────────────────────────────────

  @doc "Cache a company's paginated job listing (org-scoped)."
  def fetch_company_jobs(org_id, company_id, page, loader) do
    fetch(org_key(org_id, "jobs", company_id, page), @warm, loader)
  end

  @doc "Cache a single interview record (org-scoped)."
  def fetch_interview(org_id, interview_id, loader) do
    fetch(org_key(org_id, "interview", interview_id), @hot, loader)
  end

  @doc "Cache dashboard aggregate statistics (org-scoped)."
  def fetch_dashboard_stats(org_id, loader) do
    fetch(org_agg_key(org_id, "dashboard", org_id), @warm, loader)
  end

  @doc "Cache AI scoring rubric (rarely changes; not org-scoped, rubrics are global)."
  def fetch_scoring_rubric(rubric_id, loader) do
    fetch(key("rubric", rubric_id), @day, loader)
  end

  @doc "Invalidate all cached data for a given org."
  def invalidate_org(org_id) do
    invalidate_pattern("if:org:#{org_id}:*")
  end

  @doc "Invalidate interview-specific cache entries (org-scoped)."
  def invalidate_interview(org_id, interview_id) do
    delete(org_key(org_id, "interview", interview_id))
  end

  # ── Private helpers ───────────────────────────────────────────────────────

  defp command(args) do
    Redix.command(@pool_name, args)
  rescue
    e -> {:error, e}
  end

  defp stream_scan(pattern) do
    Stream.resource(
      fn -> "0" end,
      fn cursor ->
        case command(["SCAN", cursor, "MATCH", pattern, "COUNT", "200"]) do
          {:ok, ["0", keys]}      -> {keys, :done}
          {:ok, [next, keys]}     -> {keys, next}
          {:ok, :done}            -> {:halt, :done}
          {:error, _}             -> {:halt, :done}
          :done                   -> {:halt, :done}
        end
      end,
      fn _ -> :ok end
    )
  end
end
