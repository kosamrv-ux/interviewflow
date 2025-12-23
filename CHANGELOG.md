# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
