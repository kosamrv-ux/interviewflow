#!/usr/bin/env bash
# ============================================================
# InterviewFlow — First-time developer setup script
# ============================================================
set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo -e "${CYAN}[setup]${NC} $*"; }
success() { echo -e "${GREEN}[ok]${NC} $*"; }
warn()    { echo -e "${YELLOW}[warn]${NC} $*"; }
error()   { echo -e "${RED}[error]${NC} $*" >&2; exit 1; }

# ─── Verify prerequisites ─────────────────────────────────────────────────────

info "Checking prerequisites..."

check_command() {
  local cmd=$1 label=${2:-$1} min_version=${3:-}
  if ! command -v "$cmd" &>/dev/null; then
    error "$label is required but not installed. See README for installation instructions."
  fi
  if [[ -n "$min_version" ]]; then
    local installed_version
    installed_version=$("$cmd" --version 2>&1 | grep -oP '\d+\.\d+' | head -1 || true)
    info "$label found: $installed_version"
  else
    info "$label found"
  fi
}

check_command docker "Docker"
check_command docker compose "Docker Compose (v2)"
check_command git "Git"

# Optional but recommended
if ! command -v mix &>/dev/null; then
  warn "Elixir/Mix not found. Backend will run inside Docker only."
fi
if ! command -v node &>/dev/null; then
  warn "Node.js not found. Frontend will run inside Docker only."
fi

# ─── Environment file ─────────────────────────────────────────────────────────

info "Setting up environment..."

if [[ ! -f .env ]]; then
  cp .env.example .env
  success "Created .env from .env.example"
  warn "Please review .env and fill in any required values (Twilio, GCP credentials)."
else
  success ".env already exists — skipping"
fi

# ─── Create fake GCP credentials for local dev ────────────────────────────────

if [[ ! -f scripts/fake-gcp-credentials.json ]]; then
  cat > scripts/fake-gcp-credentials.json << 'EOF'
{
  "type": "service_account",
  "project_id": "interviewflow-local",
  "private_key_id": "dev-key-id",
  "private_key": "-----BEGIN RSA PRIVATE KEY-----\nMIIEpAIBAAKCAQEA0Z3VS5JJcds3xHn/ygWep4PAtJDiJFCZGAdSWeFIx7J7JpIO\n-----END RSA PRIVATE KEY-----\n",
  "client_email": "ai-service@interviewflow-local.iam.gserviceaccount.com",
  "client_id": "000000000000000000000",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token"
}
EOF
  success "Created fake GCP credentials for local AI service (Vertex AI will use mock mode)"
fi

# ─── Pull / build Docker images ───────────────────────────────────────────────

info "Building Docker images (this may take a few minutes on first run)..."
docker compose build --parallel

success "Docker images built"

# ─── Start infrastructure services ───────────────────────────────────────────

info "Starting database and Redis..."
docker compose up -d db redis

info "Waiting for PostgreSQL to be ready..."
max_attempts=30
attempt=0
until docker compose exec db pg_isready -U interviewflow -q 2>/dev/null; do
  attempt=$((attempt + 1))
  if [[ $attempt -ge $max_attempts ]]; then
    error "PostgreSQL did not become ready in time"
  fi
  sleep 1
done
success "PostgreSQL is ready"

info "Waiting for Redis to be ready..."
until docker compose exec redis redis-cli ping 2>/dev/null | grep -q PONG; do
  sleep 1
done
success "Redis is ready"

# ─── Run migrations ──────────────────────────────────────────────────────────

info "Starting backend for migrations..."
docker compose up -d backend

info "Waiting for Phoenix to be ready..."
max_attempts=60
attempt=0
until curl -sf http://localhost:4000/api/health &>/dev/null; do
  attempt=$((attempt + 1))
  if [[ $attempt -ge $max_attempts ]]; then
    warn "Phoenix did not respond in time — you may need to run 'make migrate' manually"
    break
  fi
  sleep 2
done

info "Running database migrations..."
docker compose exec backend mix ecto.migrate && success "Migrations complete"

info "Loading seed data..."
docker compose exec backend mix run priv/repo/seeds.exs && success "Seed data loaded"

# ─── Start remaining services ─────────────────────────────────────────────────

info "Starting frontend and AI service..."
docker compose up -d frontend ai_service

# ─── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  InterviewFlow dev environment is ready!           ${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${CYAN}Frontend:${NC}      http://localhost:3000"
echo -e "  ${CYAN}Phoenix API:${NC}   http://localhost:4000"
echo -e "  ${CYAN}LiveDashboard:${NC} http://localhost:4000/dev/dashboard"
echo -e "  ${CYAN}AI Service:${NC}    http://localhost:8000/docs"
echo ""
echo -e "  ${CYAN}Admin login:${NC}     admin@techcorp.example.com / DevAdmin123!"
echo -e "  ${CYAN}Recruiter login:${NC} recruiter@techcorp.example.com / DevRecruiter123!"
echo ""
echo -e "  Run ${YELLOW}make help${NC} to see all available commands."
echo ""
