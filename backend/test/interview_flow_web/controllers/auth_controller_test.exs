defmodule InterviewFlowWeb.AuthControllerTest do
  use InterviewFlowWeb.ConnCase, async: true

  describe "POST /api/v1/auth/register" do
    test "registers company and returns tokens with valid params", %{conn: conn} do
      params = %{
        name: "Test Company",
        slug: "test-company-#{System.unique_integer()}",
        email: "admin@testco.com",
        password: "SecurePass123!",
        password_confirmation: "SecurePass123!",
        full_name: "Test Admin"
      }

      response =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/v1/auth/register", params)

      assert response.status == 201
      body = Jason.decode!(response.resp_body)

      assert body["access_token"]
      assert body["refresh_token"]
      assert body["expires_in"] > 0
      assert body["user"]["email"] == "admin@testco.com"
      assert body["user"]["role"] == "admin"
    end

    test "returns 422 for missing required fields", %{conn: conn} do
      response =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/v1/auth/register", %{email: "bad@test.com"})

      assert response.status == 422
      body = Jason.decode!(response.resp_body)
      assert is_list(body["errors"])
      assert length(body["errors"]) > 0
    end
  end

  describe "POST /api/v1/auth/login" do
    test "authenticates with valid credentials and returns tokens", %{conn: conn} do
      user = insert(:user,
        email: "login@test.com",
        hashed_password: Bcrypt.hash_pwd_salt("CorrectHorse99!")
      )

      response =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/v1/auth/login", %{email: "login@test.com", password: "CorrectHorse99!"})

      assert response.status == 200
      body = Jason.decode!(response.resp_body)

      assert body["access_token"]
      assert body["user"]["id"] == user.id
    end

    test "returns 401 for wrong password", %{conn: conn} do
      insert(:user,
        email: "secure@test.com",
        hashed_password: Bcrypt.hash_pwd_salt("RealPass123!")
      )

      response =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/v1/auth/login", %{email: "secure@test.com", password: "WrongPass999!"})

      assert response.status == 401
      body = Jason.decode!(response.resp_body)
      assert hd(body["errors"])["code"] == "unauthorized"
    end

    test "returns 401 for non-existent email", %{conn: conn} do
      response =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/v1/auth/login", %{email: "nobody@nowhere.com", password: "AnyPass999!"})

      assert response.status == 401
    end
  end

  describe "DELETE /api/v1/auth/logout" do
    test "revokes token and returns 204", %{conn: conn} do
      user = insert(:user)

      response =
        conn
        |> authenticated_conn(user)
        |> delete("/api/v1/auth/logout")

      assert response.status == 204
    end

    test "returns 401 when not authenticated", %{conn: conn} do
      response = delete(conn, "/api/v1/auth/logout")
      assert response.status == 401
    end
  end
end
