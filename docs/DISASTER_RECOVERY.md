# Disaster Recovery Runbook

## RPO / RTO Targets

| Scenario                      | RTO     | RPO     |
|-------------------------------|---------|---------|
| Application rollback          | 5 min   | 0       |
| Database failover (HA)        | 2 min   | 0       |
| Database restore from backup  | 30 min  | 24 h    |
| Database PITR (production)    | 60 min  | 1 min   |
| Redis failure (STANDARD_HA)   | 1 min   | seconds |
| Full region outage            | 4 h     | 1 h     |

---

## Scenario 1: Application rollback

**Trigger**: New deployment causes elevated error rate or latency spike.

```bash
# 1. Detect: Grafana 5xx alert / Sentry spike / PagerDuty
# 2. Identify previous good revision
gcloud run revisions list \
  --service interviewflow-production-api \
  --region us-east1 \
  --project $PROJECT_ID \
  --format "table(name,status.observedGeneration,metadata.creationTimestamp)"

# 3. Route 100% traffic to previous revision (< 30 s)
gcloud run services update-traffic interviewflow-production-api \
  --to-revisions REVISION_NAME=100 \
  --region us-east1 \
  --project $PROJECT_ID

# 4. Verify health
curl -sf https://api.interviewflow.io/api/health | jq .

# 5. Open post-mortem doc; notify stakeholders
```

**RTO**: ~5 minutes including detection time.

---

## Scenario 2: Database failover

Cloud SQL STANDARD_HA tier provides automatic failover with:
- Synchronous replication to standby in a different zone
- Automatic failover within 2 minutes (no manual action required)
- Connection name unchanged — Cloud Run reconnects automatically

**Manual failover (for testing / planned maintenance)**:
```bash
gcloud sql instances failover interviewflow-production-db \
  --project $PROJECT_ID
```

Monitor failover completion:
```bash
gcloud sql operations list --instance=interviewflow-production-db \
  --filter="status=RUNNING" --project=$PROJECT_ID
```

---

## Scenario 3: Database restore from backup

**When**: Data corruption, accidental mass deletion, ransomware.

```bash
# List available backups
gcloud sql backups list \
  --instance interviewflow-production-db \
  --project $PROJECT_ID

# Restore to the same instance (WARNING: overwrites current data)
# First, confirm with the on-call lead and document in incident channel
gcloud sql instances restore-backup interviewflow-production-db \
  --backup-instance interviewflow-production-db \
  --backup-id BACKUP_ID \
  --project $PROJECT_ID

# Alternative: restore to a clone to inspect before cutting over
gcloud sql instances clone interviewflow-production-db \
  interviewflow-restore-$(date +%Y%m%d) \
  --project $PROJECT_ID
```

**After restore**:
1. Run `terraform plan` — output should show no resource changes
2. Run smoke test suite: `make smoke-test ENV=production`
3. Verify audit log continuity
4. Update incident document with restoration timestamp and RPO

---

## Scenario 4: Point-in-time recovery (PITR)

Available in production (enable_pitr = true). Transaction log retained 7 days.

```bash
# Clone to a specific point in time
gcloud sql instances clone interviewflow-production-db \
  interviewflow-production-pitr-$(date +%s) \
  --point-in-time "2026-04-01T14:30:00Z" \
  --project $PROJECT_ID

# Verify data integrity on clone
gcloud sql connect interviewflow-production-pitr-... \
  --user=interviewflow_app \
  --project $PROJECT_ID

# When satisfied, promote clone to primary:
# 1. Scale down Cloud Run to 0 instances (no writes)
# 2. Update DATABASE_URL in Secret Manager to point to clone
# 3. Scale Cloud Run back up
# 4. Decommission original instance
```

---

## Scenario 5: Redis (Memorystore) failure

STANDARD_HA tier provides automatic failover to replica. No manual action needed.

If failover takes longer than expected or cache is corrupt:
```bash
# Flush Redis cache (all data is reconstructable from DB)
gcloud redis instances describe interviewflow-production-redis \
  --region us-east1 --project $PROJECT_ID

# Connect via Cloud Shell and flush:
redis-cli -h REDIS_HOST -a $(gcloud secrets versions access latest \
  --secret interviewflow-production-redis-password) FLUSHALL

# Monitor: cache will warm automatically within 5-10 minutes as traffic
# hits the DB fall-through in Cache.fetch/3
```

**Impact of Redis unavailability**: All cache reads fall through to DB.
Expected DB load increase: ~4× at steady state. Cloud SQL handles this
within capacity headroom.  No data loss.

---

## Scenario 6: Full region outage (us-east1)

Multi-region failover is not fully automated. Manual procedure:

1. **Declare incident** in #incidents Slack channel, page on-call lead
2. **Provision secondary region** (us-central1):
   ```bash
   terraform apply -var="region=us-central1" -var="environment=production" \
     -var-file=dr.tfvars
   ```
3. **Promote Cloud SQL read replica** in secondary region:
   ```bash
   gcloud sql instances promote-replica interviewflow-production-db-replica-uscentral1
   ```
4. **Update DNS** to point to secondary Load Balancer IP (TTL 60s)
5. **Verify** with smoke tests
6. **Communicate** to customers via status page

**Estimated RTO**: 3-4 hours (mostly DNS propagation and data lag catch-up).
**RPO**: ~1 minute (lag between primary and async replica).

---

## DR Test Schedule

| Test                      | Frequency | Last run     | Owner          |
|---------------------------|-----------|--------------|----------------|
| Application rollback drill| Monthly   | 2026-03-15   | Platform team  |
| DB failover (manual)      | Quarterly | 2026-03-01   | Platform team  |
| Backup restore to clone   | Quarterly | 2026-02-15   | Platform team  |
| PITR restore drill        | Semi-annual| 2026-01-10  | Platform team  |
| Full DR tabletop exercise | Annual    | 2026-02-01   | Eng leadership |

---

## Contacts

| Role            | Name / Handle       | Contact           |
|-----------------|---------------------|-------------------|
| On-call primary | PagerDuty rotation  | interviewflow-prod|
| Platform lead   | @platform-team      | Slack             |
| DB admin        | @db-team            | Slack             |
| Vendor (GCP)    | Google Cloud Support| P1 support case   |
