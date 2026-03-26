/**
 * InterviewFlow — k6 Load Test Scenarios
 *
 * Simulates realistic recruiter and candidate traffic:
 *   1. Ramp-up:     0 → 50 VUs over 2 min
 *   2. Steady-state: 50 VUs for 5 min (baseline)
 *   3. Peak:        50 → 200 VUs over 2 min (simulate Monday morning rush)
 *   4. Spike:       200 → 500 VUs in 30 s (CDN miss storm simulation)
 *   5. Recovery:    500 → 50 VUs over 2 min
 *   6. Drain:       50 → 0 VUs over 1 min
 *
 * Thresholds based on March 2026 p99 targets from PERFORMANCE.md.
 */

import http from "k6/http";
import { check, group, sleep } from "k6";
import { Counter, Rate, Trend } from "k6/metrics";
import { randomIntBetween } from "https://jslib.k6.io/k6-utils/1.4.0/index.js";
import { SharedArray } from "k6/data";

// ── Config ────────────────────────────────────────────────────────────────────

const BASE_URL = __ENV.BASE_URL || "https://staging.interviewflow.io";
const API      = `${BASE_URL}/api/v1`;

// Preloaded test accounts (seeded in staging via priv/repo/seeds.exs)
const ACCOUNTS = new SharedArray("accounts", function () {
  return JSON.parse(open("../data/test_accounts.json"));
});

// ── Custom metrics ────────────────────────────────────────────────────────────

const aiScoreLatency     = new Trend("ai_score_latency_ms");
const dashboardLatency   = new Trend("dashboard_latency_ms");
const applySuccessRate   = new Rate("apply_success_rate");
const cacheHitRate       = new Rate("cache_hit_rate");
const authErrors         = new Counter("auth_errors");

// ── Stages ────────────────────────────────────────────────────────────────────

export const options = {
  stages: [
    { duration: "2m",  target: 50  },   // Ramp-up
    { duration: "5m",  target: 50  },   // Steady-state
    { duration: "2m",  target: 200 },   // Peak
    { duration: "30s", target: 500 },   // Spike
    { duration: "2m",  target: 50  },   // Recovery
    { duration: "1m",  target: 0   },   // Drain
  ],

  thresholds: {
    // API latency p99 targets (from PERFORMANCE.md post-optimization)
    "http_req_duration{endpoint:applications_list}": ["p(99)<250"],
    "http_req_duration{endpoint:interview_upcoming}": ["p(99)<80"],
    "http_req_duration{endpoint:application_detail}": ["p(99)<150"],
    "http_req_duration{endpoint:dashboard}":          ["p(99)<300"],
    "ai_score_latency_ms":                            ["p(99)<500"],

    // Error rates
    "http_req_failed":       ["rate<0.01"],  // < 1% error rate
    "apply_success_rate":    ["rate>0.99"],  // > 99% apply success
    "auth_errors":           ["count<10"],   // < 10 auth failures in run

    // Rate limiting: expect < 0.5% of requests to be rate limited
    "http_req_duration{status:429}": ["rate<0.005"],
  },
};

// ── Setup: authenticate and get tokens ───────────────────────────────────────

export function setup() {
  const tokens = [];

  // Pre-authenticate a pool of test users
  const sample = ACCOUNTS.slice(0, 20);
  for (const account of sample) {
    const res = http.post(
      `${API}/auth/login`,
      JSON.stringify({ email: account.email, password: account.password }),
      { headers: { "Content-Type": "application/json" } }
    );

    if (res.status === 200) {
      const body = JSON.parse(res.body);
      tokens.push({
        token:      body.token,
        company_id: body.user.company_id,
        user_id:    body.user.id,
      });
    } else {
      authErrors.add(1);
    }
  }

  return { tokens };
}

// ── Default scenario: recruiter browsing workflow ─────────────────────────────

export default function (data) {
  const account = data.tokens[__VU % data.tokens.length];
  if (!account) return;

  const headers = {
    "Content-Type":  "application/json",
    "Authorization": `Bearer ${account.token}`,
  };

  // Scenario: recruiter opens dashboard, browses applications, views detail
  group("recruiter_workflow", function () {

    // 1. Dashboard stats
    group("dashboard", function () {
      const start = Date.now();
      const res = http.get(`${BASE_URL}/api/analytics/dashboard`, { headers,
        tags: { endpoint: "dashboard" }
      });
      dashboardLatency.add(Date.now() - start);

      check(res, {
        "dashboard 200": (r) => r.status === 200,
      });

      // Check for cache hit header
      if (res.headers["X-Cache-Status"] === "HIT") {
        cacheHitRate.add(1);
      } else {
        cacheHitRate.add(0);
      }
    });

    sleep(randomIntBetween(1, 3));

    // 2. Applications list (first page)
    group("applications_list", function () {
      const res = http.get(`${API}/applications?status=active&limit=25&page=1`, {
        headers,
        tags: { endpoint: "applications_list" }
      });

      check(res, {
        "applications 200":          (r) => r.status === 200,
        "has pagination headers":    (r) => r.headers["X-Pagination-Has-More"] !== undefined,
        "returns data array":        (r) => JSON.parse(r.body).data?.length >= 0,
      });
    });

    sleep(randomIntBetween(2, 5));

    // 3. Application detail (random ID from a pre-seeded pool)
    group("application_detail", function () {
      const appId = __ENV.SAMPLE_APP_IDS
        ? JSON.parse(__ENV.SAMPLE_APP_IDS)[__VU % 50]
        : "test-app-id";

      const res = http.get(`${API}/applications/${appId}`, {
        headers,
        tags: { endpoint: "application_detail" }
      });

      check(res, { "application detail 200": (r) => r.status === 200 || r.status === 404 });
    });

    sleep(randomIntBetween(1, 2));

    // 4. Upcoming interviews (hot-cached, < 80 ms p99)
    group("interview_upcoming", function () {
      const res = http.get(`${API}/interviews/upcoming`, {
        headers,
        tags: { endpoint: "interview_upcoming" }
      });

      check(res, { "upcoming 200": (r) => r.status === 200 });
    });

    sleep(randomIntBetween(1, 3));
  });

  // 20% of virtual users simulate AI score polling (during active interviews)
  if (__VU % 5 === 0) {
    group("ai_score_poll", function () {
      const scoreId = __ENV.SAMPLE_SCORE_IDS
        ? JSON.parse(__ENV.SAMPLE_SCORE_IDS)[__VU % 10]
        : "test-score-id";

      const start = Date.now();
      const res   = http.get(`${API}/scores/${scoreId}`, {
        headers,
        tags: { endpoint: "score_detail" }
      });
      aiScoreLatency.add(Date.now() - start);

      check(res, { "score 200": (r) => r.status === 200 || r.status === 404 });
    });
  }
}

// ── Candidate apply scenario (separate scenario, lower VU count) ──────────────

export function applyScenario() {
  const jobIds = __ENV.SAMPLE_JOB_IDS
    ? JSON.parse(__ENV.SAMPLE_JOB_IDS)
    : ["open-job-id-1"];

  const jobId = jobIds[__VU % jobIds.length];

  const payload = JSON.stringify({
    email:       `load-test-${__VU}-${Date.now()}@example.com`,
    full_name:   `Load Test User ${__VU}`,
    phone:       "+15551234567",
    linkedin_url: "https://linkedin.com/in/loadtest",
    source:      "load-test",
    cover_letter: "This is a load test application. Please ignore.",
  });

  const res = http.post(`${API}/jobs/${jobId}/apply`, payload, {
    headers: { "Content-Type": "application/json" },
  });

  const success = check(res, {
    "apply 201": (r) => r.status === 201,
    "apply returns id": (r) => {
      try { return JSON.parse(r.body).id !== undefined; }
      catch { return false; }
    },
  });

  applySuccessRate.add(success ? 1 : 0);

  sleep(randomIntBetween(5, 15));
}

// ── Teardown: log summary ─────────────────────────────────────────────────────

export function teardown(data) {
  console.log(`Load test complete. Token pool size: ${data.tokens.length}`);
}
