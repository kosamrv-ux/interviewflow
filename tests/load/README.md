# Load Tests

## Requirements

- [k6](https://k6.io/docs/getting-started/installation/) >= 0.50
- Staging environment running with test data seeded
- `SAMPLE_APP_IDS`, `SAMPLE_JOB_IDS`, `SAMPLE_SCORE_IDS` env vars (JSON arrays)

## Running

```bash
# Against staging
BASE_URL=https://staging.interviewflow.io \
  SAMPLE_JOB_IDS='["job-uuid-1","job-uuid-2"]' \
  k6 run --config tests/load/k6.config.json tests/load/scenarios/interview_flow.js

# With HTML report
k6 run --out json=results.json tests/load/scenarios/interview_flow.js
k6 report results.json
```

## Scenarios

| Scenario          | VUs      | Duration | Purpose                    |
|-------------------|----------|----------|----------------------------|
| recruiter_workflow| 0→500    | ~13 min  | Ramp, steady, spike, drain |
| candidate_apply   | 10 req/m | 10 min   | Constant apply rate        |

## Thresholds (fail build if exceeded)

- `p(99) < 250ms` — applications list
- `p(99) < 80ms`  — upcoming interviews
- `p(99) < 150ms` — application detail
- `http_req_failed < 1%`
