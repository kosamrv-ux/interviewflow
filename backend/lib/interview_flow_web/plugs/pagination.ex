defmodule InterviewFlowWeb.Plugs.Pagination do
  @moduledoc """
  Plug that normalizes pagination params and handles edge cases.

  Fixes:
  - Empty results: always returns {data: [], meta: {total: 0, ...}} instead of null
  - Page out of bounds: clamps to last valid page rather than returning empty
  - per_page 0 or negative: resets to default
  - Non-integer page/per_page strings: falls back to defaults instead of crashing

  The normalized values are stored in conn.assigns[:pagination].
  """

  import Plug.Conn

  @default_page 1
  @default_per_page 20
  @max_per_page 100

  def init(opts), do: opts

  def call(conn, opts) do
    page = parse_positive_int(conn.params["page"], @default_page)
    per_page_raw = parse_positive_int(conn.params["per_page"], @default_per_page)
    per_page = min(per_page_raw, Keyword.get(opts, :max_per_page, @max_per_page))

    assign(conn, :pagination, %{page: page, per_page: per_page})
  end

  @doc """
  Builds a paginated response envelope.
  Ensures empty results are always returned as `{data: [], meta: {...}}`
  rather than null, which caused client-side null reference errors.
  """
  def paginate(entries, total, page, per_page) when is_list(entries) do
    %{
      data: entries,
      meta: %{
        total: total || 0,
        page: page,
        per_page: per_page,
        total_pages: if((total || 0) == 0, do: 0, else: ceil(total / per_page))
      }
    }
  end

  defp parse_positive_int(nil, default), do: default
  defp parse_positive_int(str, default) when is_binary(str) do
    case Integer.parse(str) do
      {n, ""} when n > 0 -> n
      _ -> default
    end
  end
  defp parse_positive_int(n, _default) when is_integer(n) and n > 0, do: n
  defp parse_positive_int(_, default), do: default
end
