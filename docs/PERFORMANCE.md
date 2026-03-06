# Performance Baseline & Optimization Log — March 2026

## Measurement methodology

All benchmarks run on staging (GCP Cloud Run, 2 vCPU / 4 GB, single instance,
Cloud SQL Postgres 15 db-standard-4) against a seeded 10 M row dataset.
k6 used for load generation (see `tests/load/`).  All percentiles measured
over a 5-minute steady-state window at 200 concurrent virtual users.

---

## Before optimizations (2026-03-01 baseline)

| Endpoint                       | p50    | p95     | p99     | Error % |
|-------------------------------|--------|---------|---------|---------|
| GET /api/v1/applications       | 920 ms | 2 800 ms| 4 100 ms| 0.3%    |
| GET /api/v1/interviews/upcoming| 310 ms |   780 ms| 1 640 ms| 0.0%    |
| GET /api/v1/candidates         | 740 ms | 1 900 ms| 3 200 ms| 0.1%    |
| GET /api/v1/applications/:id   | 480 ms | 1 200 ms| 2 400 ms| 0.0%    |
| AI score poll (GET /scores/:id)| 120 ms |   380 ms|   720 ms| 0.0%    |
| Dashboard stats (aggregates)   | 1 400 ms| 3 600 ms| 5 800 ms| 0.8%    |

DB connection pool utilisation peak: **94%** (pool size 20)
Average queries per request:
- `GET /applications`: 6 (N+1 on candidate/job joins)
- `GET /applications/:id`: 8 (score history re-fetched per render)

---

## After optimizations (2026-03-05)

Changes applied:
1. `20260302140000_add_performance_indexes.exs` — 10 composite/GIN indexes
2. N+1 fix in `Candidates.list_applications/2` (join + preload)
3. Redis cache layer — warm TTL for lists, hot TTL for detail
4. Cursor pagination on candidates (eliminates OFFSET scan)
5. DashboardCache single multi-aggregate SQL + warm cache

| Endpoint                       | p50   | p95    | p99    | Error % | Improvement     |
|-------------------------------|-------|--------|--------|---------|-----------------|
| GET /api/v1/applications       | 38 ms | 92 ms  | 180 ms | 0.0%    | 24× p99         |
| GET /api/v1/interviews/upcoming| 12 ms | 28 ms  | 55 ms  | 0.0%    | 30× p99         |
| GET /api/v1/candidates         | 28 ms | 68 ms  | 130 ms | 0.0%    | 25× p99         |
| GET /api/v1/applications/:id   | 22 ms | 58 ms  | 98 ms  | 0.0%    | 24× p99         |
| AI score poll (GET /scores/:id)| 4 ms  | 9 ms   | 18 ms  | 0.0%    | 40× p99 (cache) |
| Dashboard stats (aggregates)   | 45 ms | 108 ms | 210 ms | 0.0%    | 28× p99         |

DB connection pool utilisation peak: **22%** (down from 94%)
Average queries per request (cache miss): 2

---

## Cache hit rates (steady-state at 200 VU)

| Cache key pattern               | Hit rate | TTL   |
|--------------------------------|----------|-------|
| `if:upcoming_interviews:{uid}` | 96.2%    | 60 s  |
| `if:interview:{id}`            | 91.4%    | 60 s  |
| `if:applications:{co}:*`       | 88.7%    | 300 s |
| `if:candidates:{co}:*`         | 84.1%    | 300 s |
| `if:agg:dashboard:{co}`        | 95.8%    | 300 s |
| `if:agg:latest_score:{app}`    | 97.3%    | 300 s |
| `if:rubric:{job}`              | 99.8%    | 86400s|

Redis memory footprint: 42 MB at 200 VU (Memorystore Basic 1 GB tier).

---

## Remaining work

- [ ] Consider read replicas for reporting queries that bypass cache
- [ ] Evaluate materialized view for pipeline_breakdown (currently recomputed)
- [ ] Add HTTP response caching (Cache-Control: max-age) for public job board
- [ ] Investigate Cloud SQL query insights for remaining slow query tails
