# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] — 2026-06-14 — Enterprise & Ship Phase

### Added

#### Enterprise Features
- Multi-tenancy: `org_id` scoping on all resources (jobs, candidates, interviews, applications, audit logs)
- `Organizations` context with role-based access: owner, admin, member, viewer
- `OrgScope` and `RequireOrgRole` plugs for per-request tenant isolation
- SSO integration stub: Okta OIDC provider with `SSOController` for SAML/OAuth2 enterprise login
- Webhook delivery system: HMAC-SHA256 signed outgoing events with Oban retry and delivery log
- API key management: create/rotate/revoke with bcrypt-hashed storage and `if_live_` prefix
- Audit log viewer endpoint: paginated, filterable, CSV exportable (admin+ only)
- `OrganizationSettingsPage`: general, SSO, members, danger-zone tabs
- `ApiKeysPage`: create, rotate, revoke UI with one-time key reveal

#### API v2
- `/api/v2/` route structure with versioned controllers
- Consistent `{data, meta}` response envelope across all list and single-resource endpoints
- ISO8601 timestamps (was Unix integers in v1)
- Structured error responses: `{errors: [{code, message, field?}]}`
- `composite_score` field (renamed from `score` in v1)
- Interview status enum expanded: `no_show`, `rescheduled`
- OpenAPI 3.0 specification (`docs/api/openapi.yaml`)
- V1 → V2 migration guide (`docs/api/V1_TO_V2_MIGRATION.md`)

#### Integrations
- Greenhouse ATS: candidate import, stage sync, AI scorecard export
- Slack notifications: interview scheduled, scoring completed, no-show alerts
- Incoming webhook handlers for Greenhouse and Slack with signature verification
- Centralized integration error handler: rate limiting, auth failures, pool exhaustion

#### Performance
- N+1 query fix in interview listing (JOIN preload): 387ms → 18ms (p50)
- AI batch scoring with asyncio concurrency: 50 candidates 4 min → 35 sec
- Composite indexes on org-scoped query patterns (interviews, applications, audit_logs)

### Fixed
- Empty list endpoints now always return `{data: [], meta: {...}}` instead of null
- Timezone normalization for interview `scheduled_at`: always convert to UTC before storage
- Candidate ranking table sort instability on tied composite scores
- UTF-8 encoding in resume text extraction: detect and transcode Windows-1252/Latin-1
- Video preview freeze on Safari WebRTC ICE renegotiation
- Race condition in concurrent webhook delivery retry state updates (pg advisory locks)
- Org switcher selection not persisting after page refresh
- API key `last_used_at` not updating on v2 routes (api key vs JWT bearer disambiguation)
- Scheduler date picker off-by-one during DST transitions
- SSO token refresh loop on expired Okta sessions
- Audit log pagination reset on filter change
- Webhook signature verification for URL-encoded payloads
- Org_id leaking across tenant boundaries in cache keys

### Changed
- API key authentication header: `X-API-Key` deprecated in favor of `Authorization: Bearer`
- Resume URLs in v2: pre-signed GCS links (1hr TTL) returned directly in candidate response
- V1 routes deprecated — removal scheduled for 2027-05-01

### Documentation
- `docs/CONTRIBUTING.md`: full development setup, code style, PR process, migration rules
- `docs/api/openapi.yaml`: OpenAPI 3.0 spec for all v2 endpoints
- `docs/api/V1_TO_V2_MIGRATION.md`: migration checklist and per-change instructions
- `docs/adrs/ADR-008.md`: Multi-tenancy implementation decision
- `docs/adrs/ADR-009.md`: Final enterprise architecture decisions

---

## [0.5.0] — 2026-02-28 — MVP & Core Features Phase

### Added
- Production multi-stage Dockerfiles for backend, frontend, and AI service
- `PurgeExpiredSessionsWorker` — nightly cleanup of stale video sessions
- `SendInvitationWorker` — transactional email delivery for team invitations
- `Invitation` schema with secure token generation and 7-day expiry
- `CodingChallenge` schema for in-session live coding assessments (Monaco Editor)
- Invitations migration with partial unique index on pending invitations
- `Rubric` class in AI service with interview-type presets and composite scoring
- `useWebRTC` hook — encapsulates RTCPeerConnection lifecycle
- `useInterviewChannel` hook — Phoenix Channel signaling and chat management
- `useDebounce` hook — debounced input for search fields
- `CandidatesPage` — searchable, tag-filterable candidate list with add modal
- `SettingsPage` — team management, invite modal, and profile editor
- Telemetry supervisor with Ecto, Phoenix, Oban, and business-level metrics
- `.credo.exs` — strict Credo rules for readability, design, and refactoring
- `pyproject.toml` — ruff, mypy, and pytest configuration for AI service
- nginx.conf — SPA routing, WebSocket proxy, and asset caching configuration

---

## [0.4.0] — 2026-04-17 — Scale & Security Phase

### Added

#### Performance
- Redis caching layer (`InterviewFlow.Cache`) with tiered TTL: hot 60s, warm 300s, cold 1800s, day 86400s
- `DashboardCache` — single multi-aggregate SQL cached at warm TTL; 28× p99 improvement (5800ms → 210ms)
- Cursor-based keyset pagination on candidates list (eliminates OFFSET scans)
- `X-Pagination-{Page,Limit,Has-More}` response headers on all list endpoints

#### Infrastructure as Code
- Terraform root module and child modules: Cloud Run, Cloud SQL Postgres 15, Memorystore Redis 7, VPC
- GitHub Actions `deploy.yml`: parallel image builds → TF plan → env approval gate → apply → migration job → smoke test
- Kubernetes manifests for API (HPA 3–50 replicas) and Oban worker deployments
- `docs/DEPLOYMENT.md`: first-time setup, rollback, PITR restore, health check table

#### Security
- `RateLimit` plug: 7 tiered limits per IP and per user (Redis-backed Hammer)
- `SecurityHeaders` plug: CSP strict-dynamic + per-request nonce, HSTS 2-year preload, X-Frame-Options DENY
- `Cors` plug: per-environment allowlists; `Vary: Origin` to prevent CDN caching mismatches
- `InputValidation` plug: 5 MB body limit, JSON depth 6, null-byte stripping, array length cap
- Brute-force lockout: 5-attempt account lock (15 min), timing-safe with `Bcrypt.no_user_verify/0`
- `AuditLog`: async Task.Supervisor writes, PII key stripping, SIEM-compatible structured JSON logs
- `ArchiveAuditLogWorker`: weekly GCS archival of audit entries older than 90 days
- `DeadLetterReporter`: Oban discard-rate monitoring with PagerDuty P1/P2/P3 tiered alerting
- `docs/SECURITY.md`: auth, RBAC, TLS, headers, CORS, rate limiting, data protection controls

#### Load Testing
- k6 scenario: recruiter workflow (ramp 0→50→200→500 VUs), parallel candidate apply at 10 req/min
- Spike test: instant 1000 VU burst → hold → recovery; validates Cloud Run auto-scaling
- `docs/DISASTER_RECOVERY.md`: 6 DR scenarios with RTO/RPO; quarterly drill schedule

### Changed
- `Candidates.list_applications/2`: N+1 fixed; result wrapped `{:ok, %{data, meta}}`; cached at warm TTL
- `Accounts.authenticate_user/2`: brute-force lockout added (error tuples expanded)
- `Scoring.Ranking.rerank_job/1`: applies cached rubric-weighted composite scoring; invalidates app list cache
- `Jobs.JobService`: cache bust and audit log on publish/close/archive/update
- `Telemetry`: cache, rate-limit, and dead-letter metric counters added for Grafana dashboards
- Deps bumped: Phoenix 1.7.21 (CVE), Oban 2.18 (memory leak fix), Redix 1.5, Ecto SQL 3.12

### Migrations
- `20260302140000`: 10 composite/partial/GIN indexes (24-40× query p99)
- `20260320091500`: audit log indexes, user lockout columns, application export audit
- `20260409093000`: candidate search_vector tsvector with trigger; unique active-application constraint

### ADRs
- [ADR-007](docs/adrs/ADR-007.md): Redis caching with tiered TTL

---

## [0.1.0] — 2025-11-15

### Added
- Initial project scaffold: Elixir/Phoenix backend, React/TypeScript frontend, Python AI service
- Database schema for all core domain models: Company, User, Job, Candidate, Application, Interview, VideoSession, CodingChallenge, AiScore, AuditLog
- Guardian JWT authentication with access/refresh token pair
- WebRTC signaling via Phoenix Channels (offer/answer/ICE candidate relay)
- Oban background job queue for AI scoring, reminders, and notifications
- Cursor-based pagination for jobs, candidates, and applications
- Full-text search with GIN indexes and PostgreSQL tsvector columns
- AI scoring integration with Vertex AI Gemini 1.5 Pro
- Recency-weighted composite score computation across multiple interview sessions
- Pipeline-stage ranking with PostgreSQL window functions
- Rate limiting on authentication endpoints via Hammer with Redis backend
- ExMachina + Faker test factory for all domain models
- Docker Compose dev stack (PostgreSQL 15, Redis 7, Phoenix, Vite, FastAPI)
- GitHub Actions CI pipeline with matrix stages for Elixir, TypeScript, and Python
- Architecture Decision Records: ADR-001 (Elixir), ADR-002 (PostgreSQL), ADR-003 (Vertex AI)
- RFC-001 (database schema), RFC-002 (REST API design)

[Unreleased]: https://github.com/kosamrv-ux/interviewflow/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/kosamrv-ux/interviewflow/compare/v0.5.0...v1.0.0
[0.5.0]: https://github.com/kosamrv-ux/interviewflow/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/kosamrv-ux/interviewflow/compare/v0.1.0...v0.4.0
[0.1.0]: https://github.com/kosamrv-ux/interviewflow/releases/tag/v0.1.0
