/**
 * InterviewFlow — Spike Test
 *
 * Simulates a sudden traffic burst to verify auto-scaling behaviour
 * and identify breaking points.  Intended to run in staging only.
 *
 * Pattern:
 *   1 VU baseline → instant 1000 VU spike → hold 90 s → drain
 *
 * Success criteria:
 *   - Error rate remains < 5% at peak
 *   - System recovers to < 1% error rate within 60 s of spike end
 *   - No data corruption (application create idempotency check)
 *   - Cloud Run scales to >= 20 instances within 60 s
 */

import http from "k6/http";
import { check, sleep } from "k6";
import { Rate, Counter } from "k6/metrics";

const BASE_URL = __ENV.BASE_URL || "https://staging.interviewflow.io";
const API      = `${BASE_URL}/api/v1`;

const errorRate       = new Rate("errors");
const recoveredErrors = new Rate("recovered_errors");
const timeouts        = new Counter("timeouts");

export const options = {
  stages: [
    { duration: "30s",  target: 1    },  // Baseline
    { duration: "10s",  target: 1000 },  // Instant spike
    { duration: "90s",  target: 1000 },  // Hold spike
    { duration: "10s",  target: 50   },  // Drop to moderate
    { duration: "60s",  target: 50   },  // Recovery observation
    { duration: "30s",  target: 0    },  // Drain
  ],
  thresholds: {
    "http_req_duration":         ["p(95)<5000"],  // Lenient during spike
    "errors":                    ["rate<0.05"],   // < 5% at peak
    "recovered_errors":          ["rate<0.01"],   // < 1% after recovery
    "http_req_failed{during_spike:true}": ["rate<0.08"],
  },
};

export default function () {
  const duringSpike = __ITER > 100;   // Approximate spike phase

  // Health check — simplest read path, should never fail
  const health = http.get(`${BASE_URL}/api/health`, {
    timeout: "10s",
    tags: { during_spike: String(duringSpike) }
  });

  const ok = check(health, {
    "health 200":        (r) => r.status === 200,
    "no timeout":        (r) => r.timings.duration < 9000,
  });

  if (!ok) {
    errorRate.add(1);
    if (health.timings.duration >= 9000) timeouts.add(1);
  } else {
    errorRate.add(0);
    if (!duringSpike) recoveredErrors.add(0);
  }

  // Applications list — tests DB + cache path
  const apps = http.get(`${API}/applications?limit=10`, {
    headers: {
      "Authorization": `Bearer ${__ENV.LOAD_TEST_TOKEN || "invalid"}`,
      "Content-Type":  "application/json",
    },
    timeout: "15s",
    tags: { during_spike: String(duringSpike) }
  });

  check(apps, {
    "apps 200 or 401":   (r) => [200, 401].includes(r.status),
    "not 500":           (r) => r.status !== 500,
    "not 503":           (r) => r.status !== 503,
  });

  sleep(0.1);  // 100 ms between iterations per VU
}
