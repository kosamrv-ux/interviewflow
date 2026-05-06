# Migrating from API v1 to v2

## Timeline

- **2026-05-01**: v2 released, v1 enters deprecation period
- **2026-11-01**: v1 responses will include `Deprecation: true` header
- **2027-05-01**: v1 routes removed

## What Changed

### Response Envelope

**v1** returned bare objects or arrays:
```json
[{"id": "abc", "status": "scheduled", ...}]
```

**v2** wraps all responses in a consistent envelope:
```json
{
  "data": [{"id": "abc", "status": "scheduled", ...}],
  "meta": {"total": 42, "page": 1, "per_page": 20, "total_pages": 3}
}
```

**Migration**: Update your response parsing to read `.data` for the payload
and `.meta` for pagination info.

---

### Timestamps

**v1**: Unix timestamps (integer seconds since epoch)
```json
{"scheduled_at": 1746000000}
```

**v2**: ISO 8601 strings
```json
{"scheduled_at": "2026-05-01T10:00:00Z"}
```

**Migration**: Replace `new Date(ts * 1000)` with `new Date(ts)` (JS)
or use your language's ISO8601 parser directly.

---

### Candidate Score Field Rename

**v1**: `score` field
```json
{"id": "abc", "score": 87.4}
```

**v2**: `composite_score` field
```json
{"id": "abc", "composite_score": 87.4}
```

**Migration**: Find and replace all usages of `.score` on candidate objects
with `.composite_score`. The `/candidates/{id}/score` endpoint also returns
`composite_score` (was `score` in v1).

---

### Interview Status Enum Expanded

**v1** statuses: `scheduled`, `in_progress`, `completed`, `cancelled`

**v2** adds: `no_show`, `rescheduled`

**Migration**: Update any status-handling switch statements / conditionals
to handle the two new values. Treat them like `cancelled` if your application
doesn't need to distinguish them.

---

### Error Response Format

**v1** error:
```json
{"error": "Candidate not found"}
```

**v2** error:
```json
{
  "errors": [
    {"code": "not_found", "message": "Candidate not found"}
  ]
}
```

Validation errors include a `field` key:
```json
{
  "errors": [
    {"code": "validation_error", "field": "email", "message": "has already been taken"}
  ]
}
```

**Migration**: Update error handling to read `response.errors[0].message`
instead of `response.error`.

---

### Authentication Header

**v1**: `X-API-Key: if_live_yourkey`

**v2**: `Authorization: Bearer if_live_yourkey`

JWT session tokens use the same `Authorization: Bearer` header in both versions.

**Migration**: Change API key header from `X-API-Key` to `Authorization: Bearer`.

---

### Resume URLs

**v1**: Raw GCS path (required separate signed URL call)
```json
{"resume_path": "gs://interviewflow-prod/resumes/abc.pdf"}
```

**v2**: Pre-signed URL included directly (expires in 1 hour)
```json
{"resume_url": "https://storage.googleapis.com/interviewflow-prod/resumes/abc.pdf?Expires=..."}
```

**Migration**: Use `resume_url` directly. Cache the URL and re-fetch the
candidate when the URL expires (1 hour TTL).

---

## Base URL

Both v1 and v2 share the same base domain. Only the path prefix changes:

```
# v1
GET https://api.interviewflow.io/api/v1/interviews

# v2
GET https://api.interviewflow.io/api/v2/interviews
```

---

## Quick Migration Checklist

- [ ] Update base path from `/api/v1/` to `/api/v2/`
- [ ] Unwrap `.data` from all list and single-resource responses
- [ ] Add pagination using `.meta` (total, page, per_page, total_pages)
- [ ] Replace Unix timestamps with ISO8601 datetime parsing
- [ ] Rename `candidate.score` to `candidate.composite_score`
- [ ] Handle new interview statuses: `no_show`, `rescheduled`
- [ ] Update error handling to read `errors[0].message` (and optionally `errors[0].field`)
- [ ] Change API key header from `X-API-Key` to `Authorization: Bearer`
- [ ] Use `resume_url` directly (no separate signed-URL call needed)

---

## Support

Questions or issues with the migration? Open a ticket at
[support.interviewflow.io](https://support.interviewflow.io) or email
[api-support@interviewflow.io](mailto:api-support@interviewflow.io).
