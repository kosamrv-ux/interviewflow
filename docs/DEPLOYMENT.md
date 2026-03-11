# Deployment Runbook

## Architecture overview

InterviewFlow runs on GCP with three Cloud Run services behind a Global HTTPS
Load Balancer:

```
Internet
  └── Cloud Armor WAF
        └── HTTPS Load Balancer
              ├── /api/*          → interviewflow-{env}-api   (Phoenix/Elixir)
              ├── /signal/*       → interviewflow-{env}-signaling (WebRTC)
              └── /*              → Cloud Storage (React SPA)

Private VPC (10.10.0.0/20)
  ├── Cloud SQL  Postgres 15   (db-standard-4, REGIONAL HA in prod)
  ├── Memorystore Redis 7      (STANDARD_HA, 4 GB, auth + TLS)
  └── Vertex AI endpoint       (AI scoring, called from ai service)
```

---

## Prerequisites

- `gcloud` CLI authenticated with `roles/owner` for first-time setup.
- `terraform` >= 1.7 installed.
- GCS bucket `interviewflow-tf-state` already exists (created once manually).
- Workload Identity Federation pool configured for CI service account.

---

## First-time environment setup

```bash
# 1. Create TF state bucket (one-time)
gsutil mb -p $PROJECT_ID -l us-east1 gs://interviewflow-tf-state
gsutil versioning set on gs://interviewflow-tf-state

# 2. Create required secrets in Secret Manager before TF apply
gcloud secrets create interviewflow-production-secret-key-base --project=$PROJECT_ID
echo -n "$(openssl rand -base64 64)" | \
  gcloud secrets versions add interviewflow-production-secret-key-base --data-file=-

gcloud secrets create interviewflow-production-guardian-secret --project=$PROJECT_ID
echo -n "$(openssl rand -base64 48)" | \
  gcloud secrets versions add interviewflow-production-guardian-secret --data-file=-

gcloud secrets create interviewflow-production-db-password --project=$PROJECT_ID
echo -n "$(openssl rand -base64 32)" | \
  gcloud secrets versions add interviewflow-production-db-password --data-file=-

# 3. Terraform init + apply (staging first)
cd infra/terraform
terraform init -backend-config="prefix=terraform/staging/state"
terraform apply -var-file=staging.tfvars

# 4. Run DB migrations manually for first deploy
gcloud run jobs execute migrate-init \
  --region us-east1 \
  --project $PROJECT_ID
```

---

## Routine deployment (automated via GitHub Actions)

Pushes to `staging` branch auto-deploy to staging.
Pushes to `main` branch trigger the production deploy workflow which requires
manual approval in the GitHub `production` environment.

To trigger a manual deploy with a specific image tag:

1. Navigate to Actions → Deploy → Run workflow.
2. Select environment and provide image tag.

---

## Database migrations

Migrations run as a Cloud Run Job (`migrate-{sha}`) before traffic is shifted.
The job uses the same Docker image as the API with `RELEASE_COMMAND=migrate`.

To run migrations manually:

```bash
IMAGE="us-east1-docker.pkg.dev/${PROJECT_ID}/interviewflow/api:${TAG}"

gcloud run jobs create migrate-manual \
  --image "$IMAGE" \
  --region us-east1 \
  --set-env-vars RELEASE_COMMAND=migrate \
  --service-account interviewflow-production-migration-sa@${PROJECT_ID}.iam.gserviceaccount.com \
  --execute-now \
  --wait \
  --project $PROJECT_ID
```

Rolling back a migration:

```bash
# Roll back the last migration
gcloud run jobs create migrate-rollback-manual \
  --image "$IMAGE" \
  --region us-east1 \
  --set-env-vars RELEASE_COMMAND=rollback \
  --service-account ... \
  --execute-now --wait
```

---

## Rollback

### Application rollback (< 5 min RTO)

```bash
# Find previous revision
gcloud run revisions list \
  --service interviewflow-production-api \
  --region us-east1 \
  --project $PROJECT_ID

# Route 100% traffic to previous revision
gcloud run services update-traffic interviewflow-production-api \
  --to-revisions REVISION_NAME=100 \
  --region us-east1 \
  --project $PROJECT_ID
```

### Database rollback

Use the Ecto rollback migration job (see above). For data corruption, restore
from a Cloud SQL backup or PITR snapshot (production only):

```bash
gcloud sql instances restore-backup interviewflow-production-db \
  --backup-instance interviewflow-production-db \
  --backup-id BACKUP_ID \
  --project $PROJECT_ID
```

PITR restore to a point-in-time:

```bash
gcloud sql instances clone interviewflow-production-db \
  interviewflow-production-db-pitr \
  --point-in-time "2026-03-15T04:00:00Z" \
  --project $PROJECT_ID
```

---

## Health checks

| Endpoint                           | Expected response        |
|------------------------------------|--------------------------|
| GET /api/health                    | 200 `{"status":"ok"}`    |
| GET /api/v1/readiness              | 200 (DB + Redis up)      |
| Memorystore: `redis-cli PING`      | PONG                     |
| Cloud SQL: `pg_isready`            | accepting connections     |

---

## Environment variables & secrets

Never commit secrets.  All runtime secrets live in Secret Manager under the
naming convention `interviewflow-{environment}-{secret-name}`.

See `.env.example` for the full list of required environment variables and
their rotation notes.

---

## Monitoring

- Grafana dashboards: `docs/monitoring/`
- Cloud Monitoring alert policies managed via Terraform.
- On-call escalation: PagerDuty service `InterviewFlow Production`.
- Error tracking: Sentry project `interviewflow-backend`.
