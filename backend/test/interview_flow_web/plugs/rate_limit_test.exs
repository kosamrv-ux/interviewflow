defmodule InterviewFlowWeb.Plugs.RateLimitTest do
  use InterviewFlowWeb.ConnCase, async: false

  alias InterviewFlowWeb.Plugs.RateLimit

  describe "init/1" do
    test "returns opts unchanged" do
      assert RateLimit.init(tier: :login) == [tier: :login]
    end
  end

  describe "call/2 — unauthenticated tier" do
    test "adds X-RateLimit headers on allowed request" do
      conn =
        build_conn(:get, "/api/v1/candidates")
        |> put_req_header("x-forwarded-for", "1.2.3.4")
        |> RateLimit.call(tier: :unauthenticated)

      refute conn.halted
      assert get_resp_header(conn, "x-ratelimit-limit") != []
      assert get_resp_header(conn, "x-ratelimit-remaining") != []
      assert get_resp_header(conn, "x-ratelimit-reset") != []
    end
  end

  describe "call/2 — 429 response" do
    test "halts with 429 and Retry-After when limit exceeded" do
      # Exhaust the login bucket for IP 9.9.9.9 (300 req limit for unauthenticated)
      # We test the 429 branch by mocking Hammer to return {:deny, _}

      import Mock

      with_mock Hammer, [check_rate: fn _bucket, _window, _max -> {:deny, 300} end] do
        conn =
          build_conn(:post, "/api/v1/auth/login")
          |> put_req_header("x-forwarded-for", "9.9.9.9")
          |> RateLimit.call(tier: :login)

        assert conn.halted
        assert conn.status == 429
        assert get_resp_header(conn, "retry-after") != []
        assert get_resp_header(conn, "x-ratelimit-remaining") == ["0"]
      end
    end
  end

  describe "client_ip extraction" do
    test "uses last X-Forwarded-For entry as client IP" do
      # With multiple forwarded IPs (proxy chain), only the last is trusted
      conn =
        build_conn(:get, "/api/health")
        |> put_req_header("x-forwarded-for", "10.0.0.1, 172.16.0.1, 1.2.3.4")
        |> RateLimit.call(tier: :unauthenticated)

      # No assertion on exact IP (private), but ensure no crash
      refute conn.halted
    end
  end
end
