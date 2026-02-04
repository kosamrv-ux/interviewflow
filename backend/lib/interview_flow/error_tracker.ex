defmodule InterviewFlow.ErrorTracker do
  @moduledoc """
  Sentry integration for error tracking and alerting.

  Wraps Sentry SDK calls to add consistent context (user, company,
  request metadata) and to provide a single place to enable/disable
  error reporting (e.g., disabled in test environment).

  ## Setup

  1. Add `SENTRY_DSN` to `.env` and production secrets.
  2. The `Sentry.LoggerBackend` is configured in `config/runtime.exs`
     to capture all Logger.error/1 calls automatically.
  3. Use `capture_exception/2` for explicit error capture with context.
  """

  require Logger

  @enabled Application.compile_env(:interview_flow, [:sentry, :enabled], true)

  @doc """
  Captures an exception with optional context map.

  ## Options
  - `:user` — map with `id`, `email`, `role`
  - `:tags` — map of string tags for Sentry filtering
  - `:extra` — map of additional debug data

  ## Example

      ErrorTracker.capture_exception(exception,
        user: %{id: user.id, email: user.email},
        tags: %{company_id: company.id, feature: "ai_scoring"},
        extra: %{application_id: app.id}
      )
  """
  @spec capture_exception(Exception.t(), keyword()) :: :ok
  def capture_exception(exception, opts \\ []) do
    if @enabled do
      context = build_context(opts)

      Sentry.capture_exception(exception,
        extra: context.extra,
        tags: context.tags,
        user: context.user,
        stacktrace: __STACKTRACE__
      )
    end

    :ok
  end

  @doc """
  Captures a message (non-exception) at the given severity level.

  Useful for capturing business-level alerts (e.g., score service unreachable).
  """
  @spec capture_message(String.t(), keyword()) :: :ok
  def capture_message(message, opts \\ []) do
    if @enabled do
      level = Keyword.get(opts, :level, :error)
      context = build_context(opts)

      Sentry.capture_message(message,
        level: level,
        extra: context.extra,
        tags: context.tags,
        user: context.user
      )
    end

    :ok
  end

  @doc "Sets user context in Sentry scope for the current process."
  def set_user_context(user) when is_map(user) do
    if @enabled do
      Sentry.Context.set_user_context(%{
        id: Map.get(user, :id),
        email: Map.get(user, :email),
        role: Map.get(user, :role)
      })
    end

    :ok
  end

  @doc "Sets request context (request_id, path, method) in Sentry scope."
  def set_request_context(conn) do
    if @enabled do
      Sentry.Context.set_request_context(%{
        url: "#{conn.scheme}://#{conn.host}#{conn.request_path}",
        method: conn.method,
        headers: %{"x-request-id" => conn.assigns[:request_id]}
      })

      Sentry.Context.set_tags_context(%{
        request_id: conn.assigns[:request_id],
        company_id: conn.assigns[:company_id]
      })
    end

    :ok
  end

  # ── Private helpers ──────────────────────────────────────────────────────

  defp build_context(opts) do
    %{
      user: Keyword.get(opts, :user, %{}),
      tags: Keyword.get(opts, :tags, %{}),
      extra: Keyword.get(opts, :extra, %{})
    }
  end
end
