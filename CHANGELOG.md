# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

### Older (pre-scale)

### Added
- Production multi-stage Dockerfiles for backend, frontend, and AI service
- `PurgeExpiredSessionsWorker` — nightly cleanup of stale video sessions
- `SendInvitationWorker` — transactional email delivery for team invitations
- `Invitation` schema with secure token generation and 7-day expiry
- `CodingChallenge` schema for in-session live coding assessments
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

### Changed
- N/A

### Fixed
- N/A

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

[Unreleased]: https://github.com/kosamrv-ux/interviewflow/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/kosamrv-ux/interviewflow/releases/tag/v0.1.0
