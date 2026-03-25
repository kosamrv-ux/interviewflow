defmodule InterviewFlowWeb.Router do
  use InterviewFlowWeb, :router

  alias InterviewFlow.Auth.Guardian

  pipeline :api do
    plug :accepts, ["json"]
    plug :put_resp_content_type, "application/json"
    plug InterviewFlowWeb.Plugs.Cors
    plug InterviewFlowWeb.Plugs.SecurityHeaders
    plug InterviewFlowWeb.Plugs.InputValidation
    plug InterviewFlowWeb.Plugs.CorrelationId
    plug InterviewFlowWeb.Plugs.AccessLog
  end

  pipeline :authenticated do
    plug Guardian.Plug.Pipeline,
      module: Guardian,
      error_handler: InterviewFlowWeb.Auth.ErrorHandler
    plug Guardian.Plug.VerifyHeader, realm: "Bearer"
    plug Guardian.Plug.EnsureAuthenticated
    plug Guardian.Plug.LoadResource, allow_blank: false
    plug InterviewFlowWeb.Plugs.SetCurrentUser
    plug InterviewFlowWeb.Plugs.VerifyBlacklist
    plug InterviewFlowWeb.Plugs.RateLimit, tier: :authenticated
  end

  pipeline :admin_only do
    plug InterviewFlowWeb.Plugs.RequireRole, roles: ["admin"]
  end

  # ─── Health check (no auth, no rate limit) ──────────────────────────────
  scope "/api", InterviewFlowWeb do
    pipe_through :api

    get "/health",    HealthController, :check
    get "/readiness", ReadinessController, :check
  end

  # ─── Public auth endpoints (rate limited) ───────────────────────────────
  scope "/api/v1", InterviewFlowWeb do
    pipe_through :api

    post "/auth/register", AuthController, :register do
      pipe_through [InterviewFlowWeb.Plugs.RateLimit |> with_opts(tier: :register)]
    end

    post "/auth/login",   AuthController, :login
    post "/auth/refresh", AuthController, :refresh

    # Public application submission (candidate-facing)
    post "/jobs/:job_id/apply", ApplicationController, :submit
  end

  # ─── Authenticated API ───────────────────────────────────────────────────
  scope "/api/v1", InterviewFlowWeb do
    pipe_through [:api, :authenticated]

    delete "/auth/logout", AuthController, :logout

    # Current user
    get "/users/me",    UserController, :me
    patch "/users/me",  UserController, :update_me
    get "/interviews/upcoming", InterviewController, :upcoming

    # User management (admin)
    scope "/" do
      pipe_through :admin_only

      get    "/users",            UserController, :index
      post   "/users/invite",     UserController, :invite
      patch  "/users/:id/role",   UserController, :change_role
      delete "/users/:id",        UserController, :deactivate

      # Audit log (admin-only view)
      get "/audit-log", AuditLogController, :index
    end

    # Jobs
    resources "/jobs", JobController, except: [:new, :edit] do
      post "/publish", JobController, :publish
      post "/close",   JobController, :close
    end

    # Candidates
    resources "/candidates", CandidateController, except: [:new, :edit, :delete]

    # Applications
    get    "/applications",              ApplicationController, :index
    get    "/applications/:id",          ApplicationController, :show
    patch  "/applications/:id",          ApplicationController, :update
    post   "/applications/:id/advance",  ApplicationController, :advance
    post   "/applications/:id/reject",   ApplicationController, :reject
    post   "/applications/:id/hire",     ApplicationController, :hire

    # Interviews
    resources "/interviews", InterviewController, except: [:new, :edit, :delete] do
      post "/cancel", InterviewController, :cancel
      resources "/sessions", VideoSessionController, only: [:create, :show]
    end

    # Video Sessions
    get  "/sessions/:id",             VideoSessionController, :show
    get  "/sessions/:id/ice-servers", VideoSessionController, :ice_servers
    post "/sessions/:id/end",         VideoSessionController, :end_session

    # AI Scores
    get  "/applications/:application_id/scores", AiScoreController, :index
    get  "/scores/:id",                          AiScoreController, :show
    post "/scores/:id/override",                 AiScoreController, :override
  end

  # ─── LiveDashboard (dev only) ────────────────────────────────────────────
  if Application.compile_env(:interview_flow, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]
      live_dashboard "/dashboard", metrics: InterviewFlow.Telemetry
    end
  end
end
