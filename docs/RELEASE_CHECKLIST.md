# v1.0.0 Release Checklist

Pre-release checks completed before tagging v1.0.0.

## Code Quality

- [x] All CI checks green on `main`: format, lint, typecheck, test
- [x] `mix credo --strict` — 0 warnings
- [x] `mix dialyzer` — 0 errors
- [x] `npm run typecheck` — 0 TypeScript errors
- [x] `ruff check ai_service/` — 0 linting errors
- [x] All known security findings from internal audit resolved

## Database

- [x] All migrations reversible and tested with `mix ecto.rollback`
- [x] Composite indexes applied and query plans verified with EXPLAIN ANALYZE
- [x] No N+1 queries in any endpoint (verified with ExUnit + Ecto.TestRepo query logging)

## Security

- [x] SSO OIDC callback validates iss, aud, exp claims
- [x] Webhook HMAC verification covers all incoming endpoints
- [x] API keys stored as bcrypt hashes (never plaintext in DB)
- [x] org_id included in all resource queries (Credo check passing)
- [x] Cache keys include org_id namespace (no cross-tenant reads possible)
- [x] CSRF protection on all state-changing endpoints
- [x] Rate limiting verified on auth and API endpoints

## Multi-Tenancy

- [x] OrgScope plug wired into all authenticated routes
- [x] RequireOrgRole plug on admin-only endpoints (audit log, org deletion)
- [x] All context functions accept and enforce org_id
- [x] Cache invalidation clears org-scoped keys on resource updates

## API

- [x] OpenAPI spec (`docs/api/openapi.yaml`) matches actual v2 endpoint behavior
- [x] v1 deprecation header added (`Deprecation: true`, `Sunset: 2027-05-01`)
- [x] V1 → V2 migration guide reviewed and accurate
- [x] API key authentication works with `Authorization: Bearer if_live_...` header

## Integrations

- [x] Greenhouse import tested against sandbox API
- [x] Slack notification tested in dev workspace
- [x] Webhook delivery tested with test endpoint (returns 200)
- [x] SSO tested with Okta developer account

## Documentation

- [x] CHANGELOG.md updated with v1.0.0 section
- [x] README.md updated with production deployment notes
- [x] CONTRIBUTING.md complete and accurate
- [x] All ADRs written (ADR-001 through ADR-009)
- [x] OpenAPI spec complete for all v2 endpoints

## Deployment

- [x] Docker images build successfully for all services
- [x] `docker compose up` — all services healthy
- [x] Smoke test suite passes against staging environment
- [x] Rollback procedure tested (Cloud Run revision rollback)

## Final Steps

- [x] Create git tag `v1.0.0`
- [x] Push tag to GitHub
- [x] Create GitHub release from tag with CHANGELOG content
- [x] Update status page to "All Systems Operational"
- [x] Notify enterprise customers of v1.0 availability and v1 deprecation date
