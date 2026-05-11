defmodule InterviewFlow.Integrations.ErrorHandler do
  @moduledoc """
  Centralized error handling for third-party integration calls.

  Lessons from production (discovered after Greenhouse integration went live):

  1. Greenhouse returns 422 with a JSON body for validation errors, but also
     returns 422 with HTML for rate-limit edge cases. Always try JSON decode
     with fallback to raw text.

  2. HTTPoison can raise (not just return error tuples) when the connection
     pool is exhausted. Wrap all HTTP calls with a rescue clause.

  3. Greenhouse API keys expire silently; the API returns 401 without a
     `WWW-Authenticate` header. Surface this distinctly from auth errors.

  4. Slack webhook URLs become invalid when the Slack app is uninstalled,
     returning 403. Mark the integration as disabled rather than retrying.

  5. Timeouts (recv_timeout) need to be set per-call since Greenhouse can
     be slow under load (~8s observed). Default 5s is too tight.
  """

  require Logger

  @type http_result :: {:ok, map()} | {:error, integration_error()}
  @type integration_error :: {:rate_limited, retry_after: non_neg_integer()}
                            | {:auth_failed, provider: atom()}
                            | {:provider_error, status: integer(), body: String.t()}
                            | {:network_error, reason: term()}
                            | {:timeout, provider: atom()}
                            | {:integration_disabled, reason: String.t()}

  @doc """
  Wraps an HTTP response from an integration with normalized error handling.
  """
  def handle_response({:ok, %{status_code: code, body: body}}, provider)
      when code in 200..299 do
    case Jason.decode(body) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _} -> {:ok, %{raw: body}}
    end
  end

  def handle_response({:ok, %{status_code: 429, headers: headers}}, provider) do
    retry_after = extract_retry_after(headers)
    Logger.warning("[Integration:#{provider}] rate limited, retry after #{retry_after}s")
    {:error, {:rate_limited, retry_after: retry_after}}
  end

  def handle_response({:ok, %{status_code: 401}}, provider) do
    Logger.error("[Integration:#{provider}] authentication failed — API key may be expired or revoked")
    {:error, {:auth_failed, provider: provider}}
  end

  def handle_response({:ok, %{status_code: 403, body: body}}, provider) do
    Logger.error("[Integration:#{provider}] forbidden (403) — integration may be disabled: #{body}")
    {:error, {:integration_disabled, reason: body}}
  end

  def handle_response({:ok, %{status_code: code, body: body}}, provider) do
    decoded_body =
      case Jason.decode(body) do
        {:ok, d} -> d
        _ -> body
      end

    Logger.error("[Integration:#{provider}] unexpected status #{code}: #{inspect(decoded_body)}")
    {:error, {:provider_error, status: code, body: decoded_body}}
  end

  def handle_response({:error, %HTTPoison.Error{reason: :timeout}}, provider) do
    Logger.error("[Integration:#{provider}] request timed out")
    {:error, {:timeout, provider: provider}}
  end

  def handle_response({:error, %HTTPoison.Error{reason: reason}}, provider) do
    Logger.error("[Integration:#{provider}] network error: #{inspect(reason)}")
    {:error, {:network_error, reason: reason}}
  end

  @doc """
  Wraps an integration call to rescue from pool exhaustion or unexpected raises.
  """
  defmacro safe_call(provider, do: block) do
    quote do
      try do
        unquote(block)
      rescue
        e ->
          Logger.error("[Integration:#{unquote(provider)}] unexpected exception: #{Exception.message(e)}")
          {:error, {:network_error, reason: Exception.message(e)}}
      end
    end
  end

  @doc """
  Determines whether an error should be retried.
  Retryable: rate_limited, network_error, timeout
  Non-retryable: auth_failed, provider_error (4xx), integration_disabled
  """
  def retryable?({:error, {:rate_limited, _}}), do: true
  def retryable?({:error, {:network_error, _}}), do: true
  def retryable?({:error, {:timeout, _}}), do: true
  def retryable?(_), do: false

  defp extract_retry_after(headers) do
    headers
    |> Enum.find_value(fn
      {"retry-after", v} -> v
      {"Retry-After", v} -> v
      _ -> nil
    end)
    |> case do
      nil -> 60
      v -> String.to_integer(v)
    end
  end
end
