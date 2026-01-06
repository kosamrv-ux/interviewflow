defmodule InterviewFlowWeb.Plugs.RequirePermission do
  @moduledoc """
  Fine-grained permission plug for resource-level authorization.

  Permissions are defined per role as a map of `{resource, action}` tuples.
  This plug should be used inside controller `action_fallback` pipelines
  or scoped routes where the basic role check isn't sufficient.

  ## Usage

      plug InterviewFlowWeb.Plugs.RequirePermission, resource: :candidates, action: :export

  ## Permission Matrix

  | Role         | jobs          | candidates    | interviews  | ai_scores   | users        |
  |--------------|---------------|---------------|-------------|-------------|--------------|
  | admin        | full          | full          | full        | full        | full         |
  | recruiter    | read+write    | read+write    | read+write  | read        | read         |
  | interviewer  | read          | read          | read+write  | read        | –            |
  | stakeholder  | read          | read          | read        | read        | –            |
  """

  import Plug.Conn

  @permissions %{
    "admin" => :all,
    "recruiter" => %{
      jobs: [:read, :write, :publish, :close],
      candidates: [:read, :write, :export],
      applications: [:read, :write, :advance, :reject, :hire],
      interviews: [:read, :write, :cancel],
      video_sessions: [:read, :write],
      ai_scores: [:read, :override],
      users: [:read]
    },
    "interviewer" => %{
      jobs: [:read],
      candidates: [:read],
      applications: [:read],
      interviews: [:read, :write, :cancel],
      video_sessions: [:read, :write],
      ai_scores: [:read],
      users: []
    },
    "stakeholder" => %{
      jobs: [:read],
      candidates: [:read],
      applications: [:read],
      interviews: [:read],
      video_sessions: [:read],
      ai_scores: [:read],
      users: []
    }
  }

  def init(opts), do: opts

  def call(conn, opts) do
    resource = Keyword.fetch!(opts, :resource)
    action = Keyword.fetch!(opts, :action)

    case conn.assigns[:current_user] do
      nil ->
        unauthorized(conn)

      user ->
        if permitted?(user.role, resource, action) do
          conn
        else
          forbidden(conn)
        end
    end
  end

  @doc "Returns true if the given role is permitted to perform action on resource."
  def permitted?(role, resource, action) do
    case Map.get(@permissions, role) do
      :all -> true
      nil -> false
      resource_map -> action in Map.get(resource_map, resource, [])
    end
  end

  defp unauthorized(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, Jason.encode!(%{error: "authentication required"}))
    |> halt()
  end

  defp forbidden(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(403, Jason.encode!(%{error: "insufficient permissions"}))
    |> halt()
  end
end
