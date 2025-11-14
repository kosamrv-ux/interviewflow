defmodule InterviewFlowWeb.ConnCase do
  @moduledoc """
  Test case template for Phoenix controller and channel tests.
  Provides helper functions for authenticated requests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use Phoenix.ConnTest
      import Plug.Conn
      import Phoenix.ConnTest
      import InterviewFlowWeb.ConnCase
      import InterviewFlow.Factory
      alias InterviewFlowWeb.Router.Helpers, as: Routes

      @endpoint InterviewFlowWeb.Endpoint
    end
  end

  setup tags do
    InterviewFlow.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Returns a connection with a valid Authorization header for the given user.

  ## Example

      conn = authenticated_conn(conn, user)
      get(conn, "/api/v1/jobs")
  """
  def authenticated_conn(conn, user) do
    {:ok, %{access_token: token}} = InterviewFlow.Auth.Guardian.issue_token_pair(user)

    conn
    |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
    |> Plug.Conn.put_req_header("content-type", "application/json")
    |> Plug.Conn.put_req_header("accept", "application/json")
  end
end
