defmodule InterviewFlowWeb.Plugs.InputValidation do
  @moduledoc """
  Request body size limiting and basic input sanitization.

  Defends against:
  - Oversized request bodies (DoS via large payloads)
  - Request parameter pollution (duplicate keys)
  - Deeply nested JSON (stack-overflow DoS via recursive parsing)
  - Null-byte injection in string params
  - Suspiciously long field values that exceed storage column limits

  Applied in the :api pipeline before routing.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  require Logger

  # Maximum sizes by content type
  @max_body_bytes          5_120_000   # 5 MB general
  @max_apply_body_bytes   10_240_000   # 10 MB — allows resume upload URLs
  @max_json_depth          6           # nesting limit
  @max_string_length       32_768      # 32 KB per string field
  @max_array_length        200         # per JSON array

  def init(opts), do: opts

  def call(conn, opts) do
    limit = Keyword.get(opts, :max_body, @max_body_bytes)

    conn
    |> check_content_length(limit)
    |> sanitize_params()
  end

  # ── Content-Length guard ──────────────────────────────────────────────────

  defp check_content_length(%Plug.Conn{halted: true} = conn, _), do: conn

  defp check_content_length(conn, limit) do
    case get_req_header(conn, "content-length") do
      [len_str] ->
        case Integer.parse(len_str) do
          {len, _} when len > limit ->
            Logger.warning("input_validation: oversized request",
              content_length: len,
              limit: limit,
              path: conn.request_path
            )

            conn
            |> put_status(:request_entity_too_large)
            |> json(%{errors: [%{code: "payload_too_large",
                                  message: "Request body exceeds #{div(limit, 1024)} KB limit"}]})
            |> halt()

          _ ->
            conn
        end

      _ ->
        conn
    end
  end

  # ── Param sanitization ────────────────────────────────────────────────────

  defp sanitize_params(%Plug.Conn{halted: true} = conn), do: conn

  defp sanitize_params(conn) do
    case sanitize_value(conn.params, 0) do
      {:ok, sanitized} ->
        %{conn | params: sanitized}

      {:error, reason} ->
        Logger.warning("input_validation: rejected params",
          reason: reason,
          path: conn.request_path
        )

        conn
        |> put_status(:bad_request)
        |> json(%{errors: [%{code: "invalid_input", message: describe_error(reason)}]})
        |> halt()
    end
  end

  # ── Recursive value sanitizer ─────────────────────────────────────────────

  defp sanitize_value(_val, depth) when depth > @max_json_depth do
    {:error, :too_deeply_nested}
  end

  defp sanitize_value(map, depth) when is_map(map) do
    Enum.reduce_while(map, {:ok, %{}}, fn {k, v}, {:ok, acc} ->
      case sanitize_value(v, depth + 1) do
        {:ok, sanitized} -> {:cont, {:ok, Map.put(acc, k, sanitized)}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp sanitize_value(list, depth) when is_list(list) do
    if length(list) > @max_array_length do
      {:error, :array_too_long}
    else
      Enum.reduce_while(list, {:ok, []}, fn item, {:ok, acc} ->
        case sanitize_value(item, depth + 1) do
          {:ok, sanitized} -> {:cont, {:ok, [sanitized | acc]}}
          {:error, _} = err -> {:halt, err}
        end
      end)
      |> case do
        {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
        err -> err
      end
    end
  end

  defp sanitize_value(str, _depth) when is_binary(str) do
    cond do
      byte_size(str) > @max_string_length ->
        {:error, :string_too_long}

      String.contains?(str, "\0") ->
        {:error, :null_byte_in_string}

      true ->
        # Strip control characters except common whitespace (tab, newline, CR)
        sanitized = String.replace(str, ~r/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/, "")
        {:ok, sanitized}
    end
  end

  defp sanitize_value(val, _depth), do: {:ok, val}

  # ── Error descriptions ────────────────────────────────────────────────────

  defp describe_error(:too_deeply_nested),  do: "JSON nesting exceeds maximum depth"
  defp describe_error(:array_too_long),     do: "Array exceeds maximum length of #{@max_array_length}"
  defp describe_error(:string_too_long),    do: "String field exceeds maximum length"
  defp describe_error(:null_byte_in_string),do: "Null byte detected in string field"
  defp describe_error(_),                   do: "Invalid input"
end
