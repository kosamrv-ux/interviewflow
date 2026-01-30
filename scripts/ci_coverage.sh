#!/usr/bin/env bash
# ci_coverage.sh — Run tests with coverage reporting for CI.
#
# Usage:
#   ./scripts/ci_coverage.sh [--threshold 80]
#
# Environment variables:
#   COVERAGE_THRESHOLD — minimum line coverage %, default 80
#   CODECOV_TOKEN      — token for Codecov upload (optional)
#   CI                 — set by CI environments automatically

set -euo pipefail

THRESHOLD="${COVERAGE_THRESHOLD:-80}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> InterviewFlow CI Coverage Runner"
echo "==> Threshold: ${THRESHOLD}%"
echo ""

# ── Backend (Elixir) ──────────────────────────────────────────────────────

echo "--- Backend (Elixir/ExUnit) ---"
cd "${REPO_ROOT}/backend"

MIX_ENV=test mix deps.get --quiet
MIX_ENV=test mix compile --quiet

# Run with excoveralls for JSON + HTML reports
MIX_ENV=test mix coveralls.json \
  --include integration \
  --exclude skip \
  2>&1 | tee /tmp/backend_coverage.log

BACKEND_COVERAGE=$(grep -oP 'TOTAL\s+\K[\d.]+' /tmp/backend_coverage.log | tail -1 || echo "0")
echo "Backend coverage: ${BACKEND_COVERAGE}%"

# Upload to Codecov if token present
if [[ -n "${CODECOV_TOKEN:-}" ]]; then
  codecov -f cover/excoveralls.json -F backend --token "${CODECOV_TOKEN}"
fi

# ── AI Service (Python/pytest) ────────────────────────────────────────────

echo ""
echo "--- AI Service (Python/pytest) ---"
cd "${REPO_ROOT}/ai_service"

python -m pytest \
  --cov=app \
  --cov-report=xml:coverage.xml \
  --cov-report=term-missing \
  --cov-fail-under="${THRESHOLD}" \
  -v \
  tests/ \
  2>&1 | tee /tmp/python_coverage.log

PYTHON_COVERAGE=$(grep -oP 'TOTAL\s+\d+\s+\d+\s+\K\d+' /tmp/python_coverage.log | tail -1 || echo "0")
echo "AI service coverage: ${PYTHON_COVERAGE}%"

if [[ -n "${CODECOV_TOKEN:-}" ]]; then
  codecov -f coverage.xml -F ai_service --token "${CODECOV_TOKEN}"
fi

# ── Frontend (Vitest) ─────────────────────────────────────────────────────

echo ""
echo "--- Frontend (Vitest) ---"
cd "${REPO_ROOT}/frontend"

npm ci --silent
npx vitest run \
  --coverage \
  --coverage.reporter=json \
  --coverage.reporter=text \
  --coverage.reportsDirectory=./coverage \
  2>&1 | tee /tmp/frontend_coverage.log

echo ""
echo "==> Coverage Summary"
echo "    Backend  : ${BACKEND_COVERAGE}%"
echo "    AI Svc   : ${PYTHON_COVERAGE}%"
echo ""

# Fail if backend coverage is below threshold
if (( $(echo "${BACKEND_COVERAGE} < ${THRESHOLD}" | bc -l) )); then
  echo "ERROR: Backend coverage ${BACKEND_COVERAGE}% is below threshold ${THRESHOLD}%"
  exit 1
fi

echo "==> All coverage checks passed."
