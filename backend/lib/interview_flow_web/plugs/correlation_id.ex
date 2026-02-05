defmodule InterviewFlowWeb.Plugs.CorrelationId do
  @moduledoc """
  Propagates a correlation ID across distributed service calls.

  Unlike the per-request `X-Request-Id` (which is unique to each HTTP call),
  a correlation ID groups together multiple requests that belong to the same
  logical user action — e.g., scheduling an interview triggers an email job,
  a scoring job, and a channel broadcast. All of these share one correlation ID.

  ## Header
  Reads `X-Correlation-Id` from the incoming request.
  If absent, generates one and returns it in the response header.

  ## Logger metadata
  Sets `correlation_id` in Logger metadata so all downstream log lines
  (including those emitted by Oban workers) include the same correlation ID
  when it is passed in the job args.

  ## Phoenix Channel / Oban propagation
  After assignment, controllers/workers should include `correlation_id` in
  any outbound HTTP calls, Oban job args, or Channel broadcasts to maintain
  the trace across service boundaries.
  """

  import Plug.Conn
  require Logger

  @header "x-correlation-id"

  def init(opts), do: opts

  def call(conn, _opts) do
    correlation_id = get_or_generate(conn)

    Logger.metadata(correlation_id: correlation_id)

    conn
    |> put_resp_header(@header, correlation_id)
    |> assign(:correlation_id, correlation_id)
  end

  defp get_or_generate(conn) do
    case get_req_header(conn, @header) do
      [id | _] when byte_size(id) in 16..128 -> id
      _ -> new_id()
    end
  end

  defp new_id do
    :crypto.strong_rand_bytes(16)
    |> Base.hex_encode32(case: :lower, padding: false)
  end
end
