# Contributing to InterviewFlow

Thank you for your interest in contributing. This document covers how to set up your
development environment, coding conventions, and the process for submitting changes.

## Table of Contents

- [Development Setup](#development-setup)
- [Project Structure](#project-structure)
- [Running the Stack](#running-the-stack)
- [Running Tests](#running-tests)
- [Code Style](#code-style)
- [Branching and Commits](#branching-and-commits)
- [Pull Request Process](#pull-request-process)
- [Database Migrations](#database-migrations)
- [Architecture Decisions](#architecture-decisions)

---

## Development Setup

### Prerequisites

| Tool | Version |
|------|---------|
| Elixir | 1.16+ |
| Erlang/OTP | 26+ |
| Node.js | 20+ |
| Python | 3.11+ |
| PostgreSQL | 15+ |
| Docker | 24+ (for local infra) |

### First-time setup

```bash
# Clone and enter the repo
git clone https://github.com/kosamrv-ux/interviewflow.git
cd interviewflow

# Start local infrastructure (Postgres, Redis)
docker compose up -d postgres redis

# Backend setup
cd backend
mix deps.get
mix ecto.setup        # creates DB, runs migrations, seeds data
mix phx.server        # starts on http://localhost:4000

# Frontend setup (new terminal)
cd frontend
npm install
npm run dev           # starts Vite dev server on http://localhost:5173

# AI service setup (new terminal)
cd ai_service
python -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
uvicorn main:app --reload --port 8001
```

### Environment variables

Copy `.env.example` to `.env` and fill in the values:

```bash
cp .env.example .env
```

Key variables for local development:

```env
DATABASE_URL=postgres://postgres:postgres@localhost:5432/interview_flow_dev
REDIS_URL=redis://localhost:6379
SECRET_KEY_BASE=<generate with mix phx.gen.secret>
GUARDIAN_SECRET=<generate with mix phx.gen.secret>
GCS_BUCKET=interview-flow-dev-local
GCS_EMULATOR_HOST=localhost:4443   # for local GCS emulation
AI_SERVICE_URL=http://localhost:8001
```

---

## Project Structure

```
interviewflow/
├── backend/           Elixir/Phoenix API server
│   ├── lib/
│   │   ├── interview_flow/         Business logic contexts
│   │   └── interview_flow_web/     HTTP controllers, plugs, router
│   ├── priv/repo/migrations/       Ecto database migrations
│   └── test/                       ExUnit tests
├── frontend/          React 18 + TypeScript + Vite
│   └── src/
│       ├── api/        API client (axios)
│       ├── components/ Shared UI components
│       ├── hooks/      Custom React hooks
│       └── pages/      Page-level components (route targets)
├── ai_service/        Python 3.11 FastAPI AI scoring service
├── docs/
│   ├── adrs/          Architecture Decision Records
│   ├── api/           OpenAPI spec and migration guides
│   └── *.md           Architecture, deployment, security docs
├── infra/             Terraform + Docker configs
└── scripts/           Dev and ops utility scripts
```

---

## Running the Stack

```bash
# Start everything with Make
make dev

# Or individually:
make backend    # mix phx.server
make frontend   # npm run dev (in frontend/)
make ai         # uvicorn in ai_service/
make infra      # docker compose up -d
```

---

## Running Tests

```bash
# Backend (ExUnit)
cd backend
mix test
mix test --cover              # with coverage
mix test test/path/to/test.exs # single file

# Frontend (Vitest)
cd frontend
npm test
npm run test:coverage

# AI service (pytest)
cd ai_service
pytest
pytest --cov=. --cov-report=html

# All at once
make test
```

### Test conventions

- Backend: test files live in `backend/test/`, mirroring `lib/` structure.
  Use `InterviewFlow.DataCase` for DB tests, `InterviewFlowWeb.ConnCase` for controller tests.
- Frontend: tests live next to source files (`*.test.tsx`, `*.test.ts`). Use Vitest + Testing Library.
- AI service: tests in `ai_service/tests/`. Use `pytest-asyncio` for async tests.

---

## Code Style

### Elixir

- Run `mix format` before committing. CI enforces format.
- Run `mix credo --strict`. Resolve all warnings before opening a PR.
- Run `mix dialyzer` for type checking (can be slow; run locally before PR).
- Contexts are the public API of each domain — never call `Repo` from controllers directly.
- All repo queries that touch tenant data **must** include `org_id` scope. Failing to do so
  will be caught by the `InterviewFlow.Checks.UnscannedRepoGet` Credo check.

### TypeScript / React

- Run `npm run lint` (ESLint) and `npm run typecheck` (tsc --noEmit).
- Prefer named exports over default exports for components.
- Hooks must start with `use`. No business logic in page components — extract to hooks.
- Use `@tanstack/react-query` for all server state. No manual fetch in components.

### Python

- Run `ruff check .` and `black --check .` before committing.
- All async functions must use `async def`. Do not mix sync and async in service modules.
- Type all function signatures.

---

## Branching and Commits

### Branch naming

```
feat/<short-description>       New feature
fix/<short-description>        Bug fix
chore/<short-description>      Maintenance, deps, tooling
docs/<short-description>       Documentation only
perf/<short-description>       Performance improvement
refactor/<short-description>   Refactoring without feature change
```

### Commit messages

We use [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <short description>

[optional body]

[optional footer: BREAKING CHANGE, Closes #issue]
```

Types: `feat`, `fix`, `docs`, `chore`, `perf`, `refactor`, `test`, `style`

Scopes: `api`, `frontend`, `backend`, `ai`, `db`, `infra`, `auth`, `enterprise`, `integrations`

Examples:
```
feat(api): add webhook delivery system with HMAC signing
fix(frontend): fix date picker off-by-one during DST transition
perf(db): add composite indexes for org-scoped queries
docs(adrs): add ADR-008 multi-tenancy decision
```

---

## Pull Request Process

1. Open a draft PR early — this signals work in progress and invites early feedback.
2. Fill in the PR template (Summary, Test Plan, Screenshots if UI).
3. All CI checks must pass: format, lint, tests, typecheck.
4. Request review from at least one team member.
5. Squash-merge after approval. Keep the merge commit message clean.

### PR checklist

- [ ] Tests added or updated
- [ ] `mix format` and `mix credo` pass
- [ ] `npm run lint` and `npm run typecheck` pass
- [ ] Migrations are reversible (or have a documented rollback plan)
- [ ] New org-scoped queries include `org_id` where clause
- [ ] CHANGELOG.md updated if this is a user-visible change

---

## Database Migrations

- All schema changes go through Ecto migrations in `backend/priv/repo/migrations/`.
- Migrations must be reversible (`up` + `down`) unless it's truly irreversible (document why).
- For large tables: use `@disable_ddl_transaction true` and `CREATE INDEX CONCURRENTLY`.
- Never drop a column in the same migration that removes it from the schema — do it in
  a follow-up migration after the code is deployed (zero-downtime pattern).
- Run `mix ecto.migrations` to see the status of all migrations.

---

## Architecture Decisions

Significant technical decisions are documented in `docs/adrs/`. Before making a large
architectural change, check if an ADR covers it. If you're introducing a new approach
not covered by an existing ADR, write one:

```bash
cp docs/adrs/ADR-000-template.md docs/adrs/ADR-NNN-your-topic.md
```

Fill in Context, Decision, Consequences, and Alternatives Considered.

Current ADRs: ADR-001 through ADR-009.

---

## Questions?

- Open a GitHub Discussion for design questions
- Open an Issue for bugs
- Ping `#engineering` on Slack for urgent questions
