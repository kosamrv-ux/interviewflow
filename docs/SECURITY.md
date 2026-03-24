# Security Controls Documentation

## Overview

This document describes the security controls implemented in InterviewFlow as of
the Scale & Security phase (March–April 2026).  It is intended for internal
engineering teams and security auditors.

---

## Authentication & Session Management

### JSON Web Tokens (Guardian)
- Algorithm: HS512
- TTL: 8 hours (configurable via `GUARDIAN_TTL`)
- Token blacklist: expired/revoked tokens stored in Redis (Redix) with TTL matching
  original expiry
- Refresh tokens: separate 7-day tokens stored server-side; rotated on use

### Password policy
- Minimum 12 characters, maximum 72 (bcrypt limit)
- Must contain at least one uppercase letter and one number
- Passwords hashed with `Bcrypt` (cost factor 12, ~200 ms/hash)
- Timing-safe comparison via `Bcrypt.no_user_verify/0` on unknown users

### Brute-force protection
- RateLimit plug: 10 login attempts per IP per 60 seconds (Redis-backed)
- Application-layer lockout: 5 consecutive failures → 15-minute account lock
- `failed_login_count` and `locked_until` stored per user; reset on success
- All failed attempts logged to `audit_logs` with actor and IP

---

## Authorization

### Role-based access control (RBAC)
Roles: `admin`, `recruiter`, `interviewer`, `stakeholder`

| Action                    | admin | recruiter | interviewer | stakeholder |
|---------------------------|:-----:|:---------:|:-----------:|:-----------:|
| Manage users              |  ✓    |           |             |             |
| Publish / close jobs      |  ✓    |    ✓      |             |             |
| Advance / reject candidates | ✓   |    ✓      |             |             |
| View AI scores            |  ✓    |    ✓      |      ✓      |      ✓      |
| Override AI scores        |  ✓    |    ✓      |             |             |
| Export candidate data     |  ✓    |    ✓      |             |             |
| View audit log            |  ✓    |           |             |             |

All authenticated routes enforce tenant isolation: every query scopes to
`company_id` from the JWT claim — a user from company A cannot read data from
company B even with a valid token.

---

## Transport Security

### HTTPS / TLS
- TLS 1.2+ enforced at Cloud Load Balancer
- HSTS: `max-age=63072000; includeSubDomains; preload` (2-year, preload-listed)
- Cloud Run serves only over HTTPS; HTTP redirected at LB level

### Certificate management
- Certificates provisioned and auto-renewed by Google-managed SSL certificates
- No custom certificate management required

---

## HTTP Security Headers

Applied by `InterviewFlowWeb.Plugs.SecurityHeaders`:

| Header                    | Value                                                    |
|---------------------------|----------------------------------------------------------|
| Content-Security-Policy   | strict-dynamic, per-request nonce, no unsafe-inline      |
| X-Frame-Options           | DENY                                                     |
| X-Content-Type-Options    | nosniff                                                  |
| Referrer-Policy           | strict-origin-when-cross-origin                          |
| Permissions-Policy        | mic/cam restricted to /sessions/* routes                 |
| Cache-Control             | no-store (all API responses)                             |
| Strict-Transport-Security | max-age=63072000; includeSubDomains; preload              |

---

## CORS

`InterviewFlowWeb.Plugs.Cors` allows credentials only from explicitly whitelisted
origins:

- **Production**: `https://app.interviewflow.io`, `https://interviewflow.io`
- **Staging**: `https://staging.interviewflow.io`
- **Development**: `http://localhost:5173`, `http://localhost:3000`

Unknown origins receive no CORS headers (browser blocks the request).
`Vary: Origin` header prevents CDN from serving incorrect cached CORS responses.

---

## Rate Limiting

`InterviewFlowWeb.Plugs.RateLimit` uses Hammer with Redis backend for distributed
counting across Cloud Run instances:

| Scope    | Endpoint                | Limit   | Window |
|----------|-------------------------|---------|--------|
| IP       | POST /auth/login        | 10 req  | 60 s   |
| IP       | POST /auth/register     | 5 req   | 60 s   |
| IP       | POST /jobs/:id/apply    | 10 req  | 300 s  |
| IP       | Unauthenticated (global)| 300 req | 60 s   |
| User     | Authenticated (global)  | 600 req | 60 s   |
| User     | POST /scores/:id/override| 30 req | 60 s   |

Exceeded limits return `429 Too Many Requests` with `Retry-After` header.

---

## Input Validation

`InterviewFlowWeb.Plugs.InputValidation` enforces:

- Request body max 5 MB (10 MB on `/apply`)
- JSON nesting max depth: 6
- Array max length: 200 elements per level
- String field max: 32 KB
- Null byte stripping (path traversal defence)
- Control character removal

---

## Data Protection

### Encryption at rest
- Cloud SQL: Google-managed encryption keys (CMEK available on request)
- Cloud Storage: Google-managed encryption keys
- PII fields (email, phone): encrypted at column level with `cloak_ecto` (AES-256-GCM)
- MFA secrets: `cloak_ecto` encrypted binary column

### Encryption in transit
- All internal service communication via VPC private IP (no public network)
- Memorystore Redis: `SERVER_AUTHENTICATION` TLS mode enforced
- Cloud SQL: `ENCRYPTED_ONLY` SSL mode

### Data minimisation
- Audit log metadata stripped of passwords, tokens, and known PII keys
- Security log lines at WARNING do not include metadata
- Candidate PII stored only in PII-specific columns; search uses shadow columns

---

## Audit Logging

All security-sensitive operations logged to `audit_logs` table:
- Authentication events (login, logout, failed login, token refresh)
- Role changes and user deactivation
- Application pipeline movements
- AI score overrides
- Data exports (who exported what, when)
- Permission denied events

Audit logs:
- Append-only (no application-layer UPDATE/DELETE)
- Indexed for fast admin UI pagination and SIEM queries
- Archived to GCS after 90 days by `ArchiveAuditLogWorker`
- Streamed to Cloud Logging as structured JSON for SIEM integration

---

## Secrets Management

All secrets stored in GCP Secret Manager.  See `.env.example` for rotation
schedule.  Key policies:
- No secrets in Terraform state (passwords read from Secret Manager at apply time)
- No long-lived service account keys (Workload Identity Federation in CI)
- Secret versions retained 24h–7 days after rotation for drain period

---

## Vulnerability Management

- Dependency updates: `mix hex.outdated` checked weekly in CI
- `mix deps.audit` (Sobelow) runs in CI on every PR
- Sentry captures runtime errors with stack traces; PII fields redacted
- Cloud Armor WAF: OWASP Top 10 rule set enabled at LB level
- Penetration testing: scheduled annually; last test March 2026

---

## Incident Response

1. Detect: Grafana alert / PagerDuty page / Sentry error
2. Contain: `gcloud run services update-traffic` to roll back; rate limit at LB
3. Analyse: Cloud Logging audit trail, Sentry stack traces
4. Remediate: patch, deploy, verify
5. Document: post-mortem in `docs/incidents/`

Security issues: report to security@interviewflow.io (PGP key on Keybase).
