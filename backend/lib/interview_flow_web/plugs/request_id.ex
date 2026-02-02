defmodule InterviewFlowWeb.Plugs.RequestId do
  @moduledoc """
  Assigns a unique request ID to every incoming HTTP request and propagates
  it through response headers and the Logger metadata.

  The ID is taken from the `X-Request-Id` header if provided by an upstream
  load balancer (e.g., AWS ALB, nginx), otherwise a new UUID is generated.

  This ensures that all log lines emitted during a request share the same
  `request_id` field, enabling full request tracing across log aggregators
  (Datadog, CloudWatch, Loki).
  """

  import Plug.Conn
  require Logger

  @header "x-request-id"
  @response_header "x-request-id"

  def init(opts), do: opts

  def call(conn, _opts) do
    request_id = get_or_generate_id(conn)

    # Set logger metadata so all subsequent log calls include request_id
    Logger.metadata(request_id: request_id)

    conn
    |> put_resp_header(@response_header, request_id)
    |> assign(:request_id, request_id)
  end

  defp get_or_generate_id(conn) do
    case get_req_header(conn, @header) do
      [id | _] when byte_size(id) in 20..200 -> id
      _ -> generate_id()
    end
  end

  defp generate_id do
    :crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false)
  end
end
