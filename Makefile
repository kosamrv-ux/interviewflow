.PHONY: dev stop build logs migrate rollback seed test test.backend test.frontend \
        lint lint.backend lint.frontend format format.backend format.frontend \
        psql redis-cli shell.backend shell.frontend clean help

# Default target
.DEFAULT_GOAL := help

# ─── Colors ────────────────────────────────────────────────────────────────
BOLD   := \033[1m
RESET  := \033[0m
GREEN  := \033[32m
YELLOW := \033[33m
CYAN   := \033[36m

# ─── Dev Environment ───────────────────────────────────────────────────────

## dev: Start all services (DB, Redis, backend, frontend, AI service)
dev:
	@echo "$(CYAN)Starting InterviewFlow dev environment...$(RESET)"
	docker compose up

## dev.d: Start all services in detached mode
dev.d:
	docker compose up -d
	@echo "$(GREEN)Services started. Access:$(RESET)"
	@echo "  Frontend:        http://localhost:3000"
	@echo "  Phoenix API:     http://localhost:4000"
	@echo "  LiveDashboard:   http://localhost:4000/dev/dashboard"
	@echo "  AI Service:      http://localhost:8000/docs"
	@echo "  Adminer (DB UI): run 'make tools' first, then http://localhost:8080"

## tools: Start optional tooling services (Adminer)
tools:
	docker compose --profile tools up -d adminer

## stop: Stop all running services
stop:
	docker compose down

## stop.v: Stop all services and remove volumes (DESTRUCTIVE — wipes DB)
stop.v:
	@echo "$(YELLOW)WARNING: This will delete all database data!$(RESET)"
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	docker compose down -v

## logs: Tail logs from all services
logs:
	docker compose logs -f

## logs.backend: Tail Phoenix logs only
logs.backend:
	docker compose logs -f backend

## logs.frontend: Tail Vite logs only
logs.frontend:
	docker compose logs -f frontend

## logs.ai: Tail AI service logs only
logs.ai:
	docker compose logs -f ai_service

# ─── Build ─────────────────────────────────────────────────────────────────

## build: Build all Docker images for production
build:
	@echo "$(CYAN)Building production images...$(RESET)"
	docker build -t interviewflow-backend:latest ./backend
	docker build -t interviewflow-frontend:latest ./frontend
	docker build -t interviewflow-ai:latest ./ai_service

## build.backend: Rebuild backend image
build.backend:
	docker compose build backend

## build.frontend: Rebuild frontend image
build.frontend:
	docker compose build frontend

# ─── Database ──────────────────────────────────────────────────────────────

## migrate: Run pending Ecto migrations
migrate:
	docker compose exec backend mix ecto.migrate

## rollback: Roll back the last Ecto migration
rollback:
	docker compose exec backend mix ecto.rollback

## migrate.reset: Drop, create, and re-migrate the database
migrate.reset:
	@echo "$(YELLOW)WARNING: This will drop and recreate the database!$(RESET)"
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	docker compose exec backend mix ecto.reset

## seed: Load development seed data
seed:
	docker compose exec backend mix run priv/repo/seeds.exs

## psql: Open a psql shell inside the database container
psql:
	docker compose exec db psql -U interviewflow -d interviewflow_dev

## redis-cli: Open a redis-cli shell
redis-cli:
	docker compose exec redis redis-cli

# ─── Testing ───────────────────────────────────────────────────────────────

## test: Run the full test suite (backend + frontend)
test: test.backend test.frontend

## test.backend: Run Elixir tests
test.backend:
	@echo "$(CYAN)Running Elixir tests...$(RESET)"
	docker compose exec -e MIX_ENV=test backend mix test --color

## test.backend.watch: Run Elixir tests in watch mode
test.backend.watch:
	docker compose exec -e MIX_ENV=test backend mix test.watch --color

## test.frontend: Run Vitest + React Testing Library
test.frontend:
	@echo "$(CYAN)Running frontend tests...$(RESET)"
	docker compose exec frontend npm run test -- --run

## test.frontend.watch: Run frontend tests in watch mode
test.frontend.watch:
	docker compose exec frontend npm run test

## test.ai: Run Python AI service tests
test.ai:
	@echo "$(CYAN)Running AI service tests...$(RESET)"
	docker compose exec ai_service python -m pytest -v

## test.ci: Run all tests with JUnit output (for CI)
test.ci:
	docker compose exec -e MIX_ENV=test backend mix test --color --formatter ExUnit.CLIFormatter
	docker compose exec frontend npm run test -- --run --reporter=junit

# ─── Linting ───────────────────────────────────────────────────────────────

## lint: Run all linters
lint: lint.backend lint.frontend lint.ai

## lint.backend: Run Credo (Elixir linter)
lint.backend:
	@echo "$(CYAN)Linting Elixir code...$(RESET)"
	docker compose exec backend mix credo --strict

## lint.frontend: Run ESLint + TypeScript type check
lint.frontend:
	@echo "$(CYAN)Linting frontend code...$(RESET)"
	docker compose exec frontend npm run lint
	docker compose exec frontend npm run type-check

## lint.ai: Run Ruff + mypy on Python code
lint.ai:
	@echo "$(CYAN)Linting AI service code...$(RESET)"
	docker compose exec ai_service ruff check .
	docker compose exec ai_service mypy app/

# ─── Formatting ────────────────────────────────────────────────────────────

## format: Auto-format all code
format: format.backend format.frontend format.ai

## format.backend: Format Elixir code with mix format
format.backend:
	docker compose exec backend mix format

## format.frontend: Format TypeScript/CSS with Prettier
format.frontend:
	docker compose exec frontend npm run format

## format.ai: Format Python code with Ruff
format.ai:
	docker compose exec ai_service ruff format .

# ─── Shells ────────────────────────────────────────────────────────────────

## shell.backend: Open an IEx shell inside the backend container
shell.backend:
	docker compose exec backend iex -S mix

## shell.frontend: Open a shell in the frontend container
shell.frontend:
	docker compose exec frontend sh

## shell.ai: Open a shell in the AI service container
shell.ai:
	docker compose exec ai_service bash

# ─── Setup ─────────────────────────────────────────────────────────────────

## setup: First-time dev setup (copy .env, start services, migrate, seed)
setup:
	@echo "$(CYAN)Running first-time setup...$(RESET)"
	@[ -f .env ] || (cp .env.example .env && echo "$(YELLOW)Created .env from .env.example — please review it!$(RESET)")
	docker compose up -d db redis
	@echo "Waiting for database to be ready..."
	@until docker compose exec db pg_isready -U interviewflow -q; do sleep 1; done
	docker compose up -d backend
	@echo "Waiting for backend to be ready..."
	@until docker compose exec backend curl -sf http://localhost:4000/api/health > /dev/null; do sleep 2; done
	$(MAKE) migrate
	$(MAKE) seed
	docker compose up -d frontend ai_service
	@echo "$(GREEN)Setup complete!$(RESET)"
	@echo "  Frontend:     http://localhost:3000"
	@echo "  Phoenix API:  http://localhost:4000"

## clean: Remove all build artifacts and stopped containers
clean:
	docker compose down --remove-orphans
	rm -rf backend/_build backend/deps
	rm -rf frontend/dist frontend/.vite
	rm -rf ai_service/__pycache__ ai_service/.mypy_cache

# ─── Help ──────────────────────────────────────────────────────────────────

## help: Show this help message
help:
	@echo "$(BOLD)InterviewFlow — Available Make Commands$(RESET)"
	@echo ""
	@grep -E '^## ' Makefile | sed 's/## //' | awk -F: '{printf "  $(CYAN)%-25s$(RESET) %s\n", $$1, $$2}'
	@echo ""
