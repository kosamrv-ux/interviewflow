# InterviewFlow — Architecture Overview

## System Diagram

```
╔══════════════════════════════════════════════════════════════════════════════╗
║                          PUBLIC INTERNET                                      ║
║                                                                                ║
║  ┌─────────────────────────────────────────────────────────────────────────┐  ║
║  │                     GCP Cloud Load Balancer                             │  ║
║  │                     (HTTPS + WSS termination)                           │  ║
║  └───────────────────────────────┬─────────────────────────────────────────┘  ║
║                                  │                                             ║
║          ┌───────────────────────┼─────────────────────┐                      ║
║          │                       │                       │                      ║
║          ▼                       ▼                       ▼                      ║
║  ┌──────────────┐     ┌────────────────────┐   ┌──────────────────┐           ║
║  │ Cloud Run    │     │ Cloud Run          │   │ Cloud Run        │           ║
║  │ Frontend     │     │ Phoenix API        │   │ AI Scoring Svc   │           ║
║  │ (Nginx +     │     │ (Elixir 1.16)      │   │ (Python 3.11     │           ║
║  │  React SPA)  │     │                    │   │  FastAPI)        │           ║
║  └──────────────┘     │ ┌──────────────┐  │   └──────────────────┘           ║
║                        │ │ REST API     │  │            │                      ║
║                        │ │ Controllers  │  │   ┌────────┴────────┐            ║
║                        │ └──────────────┘  │   │  Vertex AI      │            ║
║                        │ ┌──────────────┐  │   │  (Gemini 1.5)   │            ║
║                        │ │ Phoenix      │  │   └─────────────────┘            ║
║                        │ │ Channels     │  │                                   ║
║                        │ │ (WebSocket)  │  │                                   ║
║                        │ └──────────────┘  │                                   ║
║                        │ ┌──────────────┐  │                                   ║
║                        │ │ Oban Workers │  │                                   ║
║                        │ │ (background  │  │                                   ║
║                        │ │  jobs)       │  │                                   ║
║                        │ └──────────────┘  │                                   ║
║                        └────────┬──────────┘                                   ║
║                                 │                                               ║
║          ┌──────────────────────┼───────────────────────┐                      ║
║          │                      │                        │                      ║
║          ▼                      ▼                        ▼                      ║
║  ┌──────────────┐     ┌──────────────────┐   ┌──────────────────┐             ║
║  │ Cloud SQL    │     │ Cloud Memorystore │   │ Cloud Storage    │             ║
║  │ PostgreSQL15 │     │ Redis 7           │   │ (recordings,     │             ║
║  │              │     │ (sessions,        │   │  resumes, assets)│             ║
║  │ Primary +    │     │  pub/sub,         │   └──────────────────┘             ║
║  │ Read Replica │     │  rate limiting)   │                                    ║
║  └──────────────┘     └──────────────────┘                                    ║
║                                                                                ║
║  ┌──────────────────────────────────────────┐                                  ║
║  │  Twilio TURN/STUN (external)             │                                  ║
║  │  P2P WebRTC fallback relay               │                                  ║
║  └──────────────────────────────────────────┘                                  ║
╚══════════════════════════════════════════════════════════════════════════════╝
```

---

## Component Responsibilities

### Frontend (React 18 + TypeScript + Vite)

**Role:** Single-page application serving recruiter and candidate interfaces.

**Key concerns:**
- `RecruiterDashboard` — pipeline kanban, bulk actions, scorecard comparison
- `InterviewRoom` — WebRTC peer connection setup, media stream management, Monaco Editor host
- `ApplicationReview` — structured scorecard display, ranking visualization (Recharts)
- `SchedulingFlow` — multi-step interview booking with calendar integration

**State management:** TanStack Query for all server state (caching, refetching, optimistic updates). React Context for auth token and active session metadata only.

**WebRTC client-side flow:**
1. Fetch Twilio TURN credentials from `GET /api/v1/sessions/:id/ice-servers`
2. Create `RTCPeerConnection` with fetched ICE config
3. Join Phoenix Channel `interview:<session_id>` over WebSocket
4. Exchange `offer`, `answer`, `ice-candidate` messages via Channel
5. On `track` event, attach remote stream to `<video>` element

---

### Backend (Elixir 1.16 + Phoenix 1.7)

**Role:** REST API, WebRTC signaling hub, background job orchestration.

**Context modules (domain boundaries):**

| Context | Responsibility |
|---------|---------------|
| `Accounts` | Users, companies, roles, Guardian JWT auth |
| `Jobs` | Job postings, pipeline stage definitions, requirements |
| `Candidates` | Candidate profiles, resume parsing, application intake |
| `Interviews` | Interview scheduling, video sessions, coding challenges |
| `Scoring` | AI score ingestion, weighted ranking, scorecard assembly |
| `Notifications` | Email/webhook dispatch via Oban |

**Phoenix Channels:**
- `InterviewChannel` (`interview:<session_id>`) — relays WebRTC signaling messages (offer/answer/ICE). Authenticated via signed token in socket params. Presence tracking shows who is in the room.
- `DashboardChannel` (`dashboard:<company_id>`) — pushes real-time pipeline events (application status changes, new scores) to recruiter dashboards.

**Oban background jobs:**
- `ScheduleReminderJob` — sends interview reminders 24h and 1h before
- `TriggerScoringJob` — calls AI service after session ends
- `SyncCalendarJob` — creates/updates Google Calendar events
- `PurgeExpiredSessionsJob` — cleans up VideoSession records older than retention policy

---

### AI Scoring Service (Python 3.11 + FastAPI)

**Role:** Transcript and code analysis; produces structured `AiScore` records.

**Endpoints:**
- `POST /score` — accepts transcript JSON + code submission, returns scorecard
- `GET /health` — liveness probe

**Scoring pipeline:**
1. Receive `ScoringRequest` (session_id, transcript segments, code_submission, rubric)
2. Construct prompt from rubric template; call Vertex AI Gemini 1.5 Pro
3. Parse structured JSON response into `ScoreBreakdown` (per-competency 1–10 scores + rationale)
4. Return to Phoenix, which persists as `AiScore` record

**Competency dimensions scored:**
- `technical_depth` — correctness, algorithmic thinking, code quality
- `communication` — clarity, conciseness, active listening
- `problem_solving` — approach, decomposition, edge case handling
- `culture_fit` — values alignment, collaboration signals
- `role_fit` — domain knowledge relative to job requirements

---

### Database (PostgreSQL 15)

**Schema overview:**

```
companies ──< jobs ──< applications ──< interviews ──< video_sessions
                                   └──< ai_scores
candidates ──< applications
users >── companies
coding_challenges ──< coding_submissions
```

Key design decisions:
- `applications.pipeline_stage` uses a `VARCHAR` enum (not PG ENUM type) for zero-downtime stage additions
- `ai_scores.breakdown` stored as `JSONB` — flexible per-rubric structure without schema churn
- `video_sessions.ice_candidates` stored as `JSONB[]` for signaling replay in lossy connections
- All tables use `UUID` primary keys for distributed-safe ID generation
- Soft deletes on `companies`, `jobs`, `candidates` (deleted_at) — never hard-delete business records
- Audit log via `audit_logs` table; trigger-based for score and status changes

---

## Data Flow Diagrams

### Application Submission Flow

```
Candidate          Frontend          Phoenix API       PostgreSQL
    │                  │                  │                 │
    │──[fill form]─────▶                  │                 │
    │                  │──POST /apply────▶│                 │
    │                  │                  │─INSERT candidate│
    │                  │                  │─INSERT application
    │                  │                  │─INSERT audit_log│
    │                  │                  │──commit─────────▶
    │                  │                  │──enqueue email job
    │                  │◀─201 Created────-│                 │
    │◀─confirmation────│                  │                 │
```

### Live Interview + Scoring Flow

```
Recruiter   Candidate   Phoenix Channel   Oban   AI Service   Vertex AI
    │            │             │            │          │            │
    │──join──────────────────▶ │            │          │            │
    │            │──join──────▶│            │          │            │
    │◀─presence_state──────────│            │          │            │
    │──[SDP offer]────────────▶│            │          │            │
    │            │◀─[offer]────│            │          │            │
    │            │──[answer]──▶│            │          │            │
    │◀─[answer]───────────────-│            │          │            │
    │    ◀─────── ICE exchange ────────────▶│          │            │
    │            │  (P2P video established) │          │            │
    ~~~~~~~~~~~~~~~~~~~ interview in progress ~~~~~~~~~~~~~~~~~~~   │
    │──[end session]──────────▶│            │          │            │
    │            │             │──enqueue──▶│          │            │
    │            │             │            │──POST /score──────────▶
    │            │             │            │          │──prompt────▶
    │            │             │            │          │◀─response──│
    │            │             │            │◀─scorecard─│           │
    │            │             │──INSERT AiScore        │            │
    │◀─scorecard_ready─────────│            │          │            │
```

---

## Scaling Notes

### Horizontal Scaling Constraints

**Phoenix (stateful WebSockets):** Phoenix Channels use distributed Elixir PubSub backed by Redis (via `phoenix_pubsub_redis`). Multiple Phoenix instances can be deployed behind the load balancer with WebSocket stickiness enabled — messages published on one node fan out to subscribers on all nodes via Redis pub/sub.

**AI Service:** Stateless FastAPI. Scale to zero during off-hours; autoscale on Cloud Run based on concurrent request count. Vertex AI calls are the bottleneck; implement request queuing in Oban rather than hitting AI service synchronously from interviews.

**Database:** Cloud SQL with one read replica. Analytics queries (ranking, dashboard aggregations) routed to replica via Ecto's `replica: true` repo. Write volume is modest (interviews are not high-frequency transactions).

### Performance Targets

| Metric | Target |
|--------|--------|
| API p99 latency | < 200ms |
| WebRTC signaling round-trip | < 100ms |
| AI scoring completion | < 30s post-session |
| Dashboard page load (cached) | < 1s |
| Concurrent video sessions | 500 (MVP), 5000 (Series A) |

### Security Considerations

- All API endpoints require Bearer JWT (Guardian); tokens expire in 1h, refresh tokens in 7d
- Phoenix Channel join events require signed `session_token` param validated against DB
- Twilio TURN credentials are ephemeral (TTL 86400s), fetched per-session server-side
- Video recordings encrypted at rest in Cloud Storage; KMS-managed keys
- PII fields (candidate email, phone) encrypted at application layer using Cloak/AES-256-GCM
- Rate limiting on auth endpoints via Redis token bucket (Hammer library)
