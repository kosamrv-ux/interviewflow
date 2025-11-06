# InterviewFlow

![CI](https://github.com/kosamrv-ux/interviewflow/workflows/CI/badge.svg)
![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Elixir](https://img.shields.io/badge/Elixir-1.16-purple.svg)
![React](https://img.shields.io/badge/React-18-blue.svg)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-15-blue.svg)

End-to-end video interview and AI-powered candidate assessment platform for modern HR teams.

InterviewFlow enables recruiters to conduct structured video interviews with real-time WebRTC streaming, administer coding assessments in-browser, and receive instant AI-generated scorecards that rank candidates against job-specific rubrics — all from a single unified dashboard.

---

## Features

- **Live Video Interviews** — browser-native WebRTC sessions with no plugin required; TURN relay via Twilio for NAT traversal
- **Coding Assessments** — Monaco Editor (VS Code engine) embedded in-session; multi-language execution sandbox
- **AI Scoring Engine** — Python service on GCP Vertex AI analyzes transcripts and code submissions, producing structured scorecards with per-competency breakdowns
- **Candidate Ranking** — weighted composite scores across technical, communication, and culture-fit dimensions; drag-to-reorder override
- **Recruiter Dashboard** — pipeline kanban view, scorecard comparison, bulk status updates, offer-letter generation
- **Automated Scheduling** — Oban-powered background jobs sync with Google Calendar / Outlook; sends calendar invites and reminders
- **Role-Based Access** — Company admin, Recruiter, Interviewer, and read-only Stakeholder roles with fine-grained permissions
- **Audit Trail** — every state transition, score update, and user action is immutably logged for compliance

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           Browser (Recruiter / Candidate)                │
│                                                                           │
│  ┌─────────────────────┐          ┌─────────────────────────────────┐   │
│  │  React 18 + Vite    │          │   Monaco Editor (code assess.)  │   │
│  │  TanStack Query     │          │   WebRTC PeerConnection         │   │
│  │  React Router v6    │          │   MediaStream API               │   │
│  └────────┬────────────┘          └──────────────┬──────────────────┘   │
│           │ REST / JSON                          │ WebRTC (DTLS/SRTP)   │
└───────────┼──────────────────────────────────────┼─────────────────────┘
            │                                      │
            ▼                                      ▼
┌────────────────────────────────────────────────────────────────────────┐
│                  GCP Cloud Run — Phoenix API + Signaling               │
│                                                                         │
│  ┌──────────────────┐   ┌──────────────────┐   ┌──────────────────┐   │
│  │  REST API        │   │  Phoenix Channels │   │  Oban Workers    │   │
│  │  (Guardian JWT)  │   │  (WebRTC signal) │   │  (scheduling,    │   │
│  │                  │   │  (LiveSession)   │   │   notifications) │   │
│  └──────┬───────────┘   └──────────────────┘   └──────────────────┘   │
│         │                                                                │
└─────────┼──────────────────────────────────────────────────────────────┘
          │
    ┌─────┴──────┐         ┌───────────────────┐    ┌─────────────────┐
    │ Cloud SQL  │         │  Vertex AI /       │    │  Cloud Storage  │
    │ PostgreSQL │         │  Python AI Service │    │  (recordings,   │
    │ 15         │         │  (scoring, ranking)│    │   resumes)      │
    └────────────┘         └───────────────────┘    └─────────────────┘
          │
    ┌─────┴──────┐
    │   Redis    │
    │ (sessions, │
    │  pub/sub)  │
    └────────────┘
                                ┌─────────────────┐
                                │  Twilio TURN    │
                                │  (NAT traversal)│
                                └─────────────────┘
```

### Data Flow — Live Interview

1. Recruiter opens interview room → React calls `POST /api/v1/sessions` → Phoenix creates `VideoSession` record
2. Phoenix Channel (`InterviewChannel`) receives `join` event; broadcasts ICE candidates via Redis pub/sub to all participants
3. Candidate browser establishes WebRTC `RTCPeerConnection` using ICE servers from Twilio TURN credentials API
4. Audio/video streams flow peer-to-peer (DTLS-SRTP); Phoenix only handles signaling
5. On session end, Phoenix publishes `session.ended` event → Oban job uploads recording to Cloud Storage, triggers AI scoring
6. Python AI service receives transcript + code submission → Vertex AI → returns `AiScore` JSON → stored in PostgreSQL

---

## Local Development

### Prerequisites

| Tool | Version |
|------|---------|
| Docker + Docker Compose | 24+ |
| Elixir | 1.16+ |
| Erlang/OTP | 26+ |
| Node.js | 20 LTS |
| Python | 3.11+ |
| Make | any |

### Quick Start

```bash
# 1. Clone the repo
git clone https://github.com/kosamrv-ux/interviewflow.git
cd interviewflow

# 2. Copy environment variables
cp .env.example .env
# Edit .env — at minimum set TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN

# 3. Start all services (DB, Redis, backend, frontend, AI service)
make dev

# 4. In another terminal, run migrations and seed data
make migrate
make seed

# 5. Open the app
open http://localhost:3000        # Frontend
open http://localhost:4000/api   # Phoenix API
```

### Service URLs (development)

| Service | URL |
|---------|-----|
| Frontend (Vite) | http://localhost:3000 |
| Phoenix API | http://localhost:4000 |
| Phoenix LiveDashboard | http://localhost:4000/dev/dashboard |
| PostgreSQL | localhost:5432 |
| Redis | localhost:6379 |
| AI Service (FastAPI) | http://localhost:8000 |

---

## Docker Compose

The full development stack is defined in `docker-compose.yml`. Key services:

```
db          PostgreSQL 15 with persistent volume
redis       Redis 7 for session state and pub/sub
backend     Phoenix app with file-watch reload
frontend    Vite dev server with HMR
ai_service  Python FastAPI scoring service
```

```bash
# Start all services
docker compose up

# Start only infrastructure (DB + Redis)
docker compose up db redis

# Rebuild a single service after dependency changes
docker compose build backend
docker compose up backend
```

---

## Makefile Commands

| Command | Description |
|---------|-------------|
| `make dev` | Start all Docker services |
| `make stop` | Stop all services |
| `make migrate` | Run pending Ecto migrations |
| `make rollback` | Roll back last migration |
| `make seed` | Load development seed data |
| `make test` | Run full test suite (backend + frontend) |
| `make test.backend` | Elixir tests only |
| `make test.frontend` | Vitest + React Testing Library |
| `make lint` | Run all linters |
| `make format` | Auto-format all code |
| `make build` | Build production Docker images |
| `make logs` | Tail all service logs |
| `make psql` | Open psql shell in DB container |

---

## Environment Variables

See `.env.example` for the full list with comments. Key variables:

| Variable | Description |
|----------|-------------|
| `DATABASE_URL` | PostgreSQL connection string |
| `REDIS_URL` | Redis connection URL |
| `SECRET_KEY_BASE` | Phoenix secret (64+ chars, `mix phx.gen.secret`) |
| `GUARDIAN_SECRET_KEY` | JWT signing secret |
| `TWILIO_ACCOUNT_SID` | Twilio account for TURN credentials |
| `TWILIO_AUTH_TOKEN` | Twilio auth token |
| `GCP_PROJECT_ID` | GCP project for Vertex AI and Cloud Storage |
| `GCS_BUCKET_NAME` | Cloud Storage bucket for recordings |
| `VERTEX_AI_ENDPOINT` | Vertex AI prediction endpoint URL |
| `AI_SERVICE_URL` | Internal URL of the Python scoring service |

---

## API Overview

All endpoints are versioned under `/api/v1`. Authentication uses Bearer JWT tokens issued by `POST /api/v1/auth/login`.

### Authentication
| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/v1/auth/register` | Register new company account |
| POST | `/api/v1/auth/login` | Login, receive JWT |
| POST | `/api/v1/auth/refresh` | Refresh access token |
| DELETE | `/api/v1/auth/logout` | Revoke token |

### Jobs
| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/v1/jobs` | List jobs for company |
| POST | `/api/v1/jobs` | Create job posting |
| GET | `/api/v1/jobs/:id` | Get job with applications |
| PATCH | `/api/v1/jobs/:id` | Update job |
| DELETE | `/api/v1/jobs/:id` | Archive job |

### Candidates & Applications
| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/v1/applications` | List applications (filterable) |
| POST | `/api/v1/jobs/:job_id/applications` | Submit application |
| GET | `/api/v1/applications/:id` | Get application with scores |
| PATCH | `/api/v1/applications/:id/status` | Advance pipeline stage |

### Interviews
| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/v1/interviews` | Schedule interview |
| GET | `/api/v1/interviews/:id` | Get interview details |
| POST | `/api/v1/interviews/:id/sessions` | Create video session |
| GET | `/api/v1/interviews/:id/scorecard` | Get AI scorecard |

### WebSocket Channels
| Channel | Topic | Description |
|---------|-------|-------------|
| `InterviewChannel` | `interview:<session_id>` | WebRTC signaling, ICE candidates |
| `DashboardChannel` | `dashboard:<company_id>` | Real-time pipeline updates |

---

## Project Structure

```
interviewflow/
├── backend/                    # Elixir Phoenix application
│   ├── config/                 # Environment configs
│   ├── lib/
│   │   ├── interview_flow/     # Core business logic (contexts)
│   │   │   ├── accounts/       # Users, companies, auth
│   │   │   ├── jobs/           # Job postings, pipeline stages
│   │   │   ├── candidates/     # Candidate profiles, applications
│   │   │   ├── interviews/     # Interview scheduling, sessions
│   │   │   └── scoring/        # AI score retrieval and aggregation
│   │   └── interview_flow_web/ # Phoenix web layer
│   │       ├── channels/       # WebRTC signaling channels
│   │       ├── controllers/    # REST API controllers
│   │       └── router.ex
│   ├── priv/repo/migrations/   # Ecto migrations
│   └── test/
├── frontend/                   # React 18 + TypeScript + Vite
│   ├── src/
│   │   ├── api/                # Typed API client (Axios + TanStack Query)
│   │   ├── components/         # Reusable UI components
│   │   ├── pages/              # Route-level page components
│   │   └── hooks/              # Custom React hooks
│   └── public/
├── ai_service/                 # Python FastAPI scoring service
│   ├── app/
│   │   ├── scoring/            # Vertex AI integration
│   │   └── models/             # Pydantic schemas
│   └── tests/
├── docs/
│   ├── ARCHITECTURE.md
│   ├── adrs/                   # Architecture Decision Records
│   └── rfcs/                   # Request for Comments
├── scripts/                    # Dev tooling scripts
├── docker-compose.yml
├── Makefile
└── .env.example
```

---

## Contributing

1. Fork the repository and create a feature branch: `git checkout -b feat/my-feature`
2. Follow the commit convention: `type(scope): description` (e.g., `feat(api): add interview scoring endpoint`)
3. Ensure all tests pass: `make test`
4. Ensure linting passes: `make lint`
5. Open a pull request against `main` with a clear description of the change and any relevant screenshots or API output

### Commit Types
- `feat` — new feature
- `fix` — bug fix
- `docs` — documentation only
- `chore` — tooling, dependencies, config
- `test` — adding or updating tests
- `refactor` — code change that neither fixes a bug nor adds a feature
- `perf` — performance improvement

---

## License

MIT License. See [LICENSE](LICENSE) for details.
