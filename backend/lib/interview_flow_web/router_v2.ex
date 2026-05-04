defmodule InterviewFlowWeb.RouterV2 do
  @moduledoc """
  API v2 route definitions.

  V2 changes from V1:
  - All list endpoints return `{data: [...], meta: {pagination}}` envelope
  - Timestamps are ISO8601 strings (was unix integers in v1)
  - Error responses use `{errors: [{code, message, field?}]}` format
  - Candidate score field renamed: `score` -> `composite_score`
  - Interview status enum expanded: added `no_show`, `rescheduled`
  - Webhook event types included in list responses
  - API keys authenticated via `Authorization: Bearer` (was `X-API-Key` in v1)

  V1 routes remain active and will be deprecated on 2027-05-01.
  """

  import Phoenix.Router

  alias InterviewFlowWeb.Plugs.{AuthPlug, OrgScope, RequireOrgRole}

  # These macros are called from the main router
  defmacro v2_routes do
    quote do
      scope "/api/v2", InterviewFlowWeb.V2 do
        pipe_through [:api, :auth_required, :org_scoped]

        # Interviews
        resources "/interviews", InterviewControllerV2, except: [:new, :edit]
        post "/interviews/:id/complete", InterviewControllerV2, :complete
        post "/interviews/:id/cancel", InterviewControllerV2, :cancel
        get "/interviews/:id/recording", InterviewControllerV2, :recording

        # Candidates
        resources "/candidates", CandidateControllerV2, except: [:new, :edit]
        get "/candidates/:id/score", CandidateControllerV2, :score
        get "/candidates/:id/timeline", CandidateControllerV2, :timeline

        # Jobs
        resources "/jobs", JobControllerV2, except: [:new, :edit]
        get "/jobs/:id/candidates", JobControllerV2, :candidates
        get "/jobs/:id/ranking", JobControllerV2, :ranking

        # Applications
        resources "/applications", ApplicationControllerV2, except: [:new, :edit]
        patch "/applications/:id/stage", ApplicationControllerV2, :update_stage

        # Organization
        get "/organization", OrganizationControllerV2, :show
        put "/organization", OrganizationControllerV2, :update
        get "/organization/members", OrganizationControllerV2, :members
        get "/organization/stats", OrganizationControllerV2, :stats

        # API Keys
        resources "/api-keys", ApiKeyControllerV2, except: [:new, :edit, :update]
        post "/api-keys/:id/rotate", ApiKeyControllerV2, :rotate
        delete "/api-keys/:id", ApiKeyControllerV2, :revoke

        # Webhooks
        resources "/webhooks", WebhookControllerV2, except: [:new, :edit]
        post "/webhooks/:id/test", WebhookControllerV2, :test_delivery
        get "/webhooks/:id/logs", WebhookControllerV2, :delivery_logs

        # Audit Log (admin+ only)
        scope "/audit-log" do
          pipe_through [:require_admin]
          get "/", AuditLogControllerV2, :index
          get "/:id", AuditLogControllerV2, :show
          get "/export", AuditLogControllerV2, :export
        end
      end
    end
  end
end
