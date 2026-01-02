defmodule InterviewFlowWeb.Plugs.VerifyBlacklist do
  @moduledoc """
  Plug that rejects requests whose JWT has been blacklisted (e.g. after logout).

  Must be placed **after** `Guardian.Plug.VerifyHeader` so that the token
  claims are already decoded and available via `Guardian.Plug.current_claims/1`.
  """

  import Plug.Conn
  alias InterviewFlow.Auth.TokenBlacklist

  def init(opts), do: opts

  def call(conn, _opts) do
    case Guardian.Plug.current_claims(conn) do
      nil ->
        conn

      claims ->
        jti = Map.get(claims, "jti")

        if jti && TokenBlacklist.member?(jti) do
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(401, Jason.encode!(%{error: "token has been revoked"}))
          |> halt()
        else
          conn
        end
    end
  end
end
