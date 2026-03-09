locals {
  name_prefix = "interviewflow-${var.environment}"
  common_labels = {
    app         = "interviewflow"
    environment = var.environment
    managed_by  = "terraform"
  }
}

# ── Networking ────────────────────────────────────────────────────────────────

module "networking" {
  source = "./modules/networking"

  project_id   = var.project_id
  region       = var.region
  network_name = var.vpc_network
  name_prefix  = local.name_prefix
  labels       = local.common_labels
}

# ── Cloud SQL (PostgreSQL 15) ─────────────────────────────────────────────────

module "database" {
  source = "./modules/cloud_sql"

  project_id       = var.project_id
  region           = var.region
  name             = "${local.name_prefix}-db"
  database_tier    = var.db_tier
  db_name          = var.db_name
  db_user          = var.db_user
  network_id       = module.networking.network_id
  labels           = local.common_labels

  # Point-in-time recovery and 7-day retained backups in production
  enable_pitr      = var.environment == "production"
  backup_count     = var.environment == "production" ? 7 : 3
}

# ── Memorystore (Redis 7.x) ───────────────────────────────────────────────────

module "cache" {
  source = "./modules/memorystore"

  project_id     = var.project_id
  region         = var.region
  name           = "${local.name_prefix}-redis"
  tier           = var.redis_tier
  memory_size_gb = var.redis_memory_gb
  network_id     = module.networking.network_id
  labels         = local.common_labels

  # STANDARD_HA provides replica for HA; BASIC adequate for staging
  replica_count  = var.environment == "production" ? 1 : 0
  auth_enabled   = true
  transit_encryption_mode = "SERVER_AUTHENTICATION"
}

# ── Cloud Run: Phoenix API ────────────────────────────────────────────────────

module "api_service" {
  source = "./modules/cloud_run"

  project_id      = var.project_id
  region          = var.region
  name            = "${local.name_prefix}-api"
  image           = var.app_image
  labels          = local.common_labels

  min_instances   = var.api_min_instances
  max_instances   = var.api_max_instances
  concurrency     = var.api_concurrency
  cpu             = "2000m"
  memory          = "2Gi"

  # Cloud SQL sidecar connection
  cloudsql_instances = [module.database.connection_name]

  vpc_connector   = module.networking.vpc_connector_id

  env_vars = {
    DATABASE_URL        = "ecto://#{var.db_user}@/cloudsql/${module.database.connection_name}/${var.db_name}"
    REDIS_URL           = "redis://${module.cache.host}:${module.cache.port}"
    PHX_HOST            = "${local.name_prefix}.interviewflow.io"
    ENVIRONMENT         = var.environment
    AI_SERVICE_URL      = module.ai_service.url
    ALLOWED_ORIGINS     = join(",", var.allowed_origins)
  }

  # Secrets from Secret Manager — injected as env vars at runtime
  secrets = {
    SECRET_KEY_BASE       = "${local.name_prefix}-secret-key-base:latest"
    DATABASE_PASSWORD     = "${local.name_prefix}-db-password:latest"
    GUARDIAN_SECRET_KEY   = "${local.name_prefix}-guardian-secret:latest"
    TWILIO_AUTH_TOKEN     = "${local.name_prefix}-twilio-auth-token:latest"
    AI_SERVICE_SECRET     = "${local.name_prefix}-ai-service-secret:latest"
    SENTRY_DSN            = "${local.name_prefix}-sentry-dsn:latest"
    REDIS_PASSWORD        = "${local.name_prefix}-redis-password:latest"
  }

  liveness_probe = {
    http_get = { path = "/api/health" }
    initial_delay_seconds = 10
    period_seconds        = 15
  }

  startup_probe = {
    http_get              = { path = "/api/health" }
    failure_threshold     = 6
    period_seconds        = 10
  }
}

# ── Cloud Run: Python AI Scoring Service ─────────────────────────────────────

module "ai_service" {
  source = "./modules/cloud_run"

  project_id      = var.project_id
  region          = var.region
  name            = "${local.name_prefix}-ai"
  image           = var.ai_image
  labels          = local.common_labels

  min_instances   = var.ai_min_instances
  max_instances   = var.ai_max_instances
  concurrency     = 4       # GPU-bound; low concurrency per instance
  cpu             = "4000m"
  memory          = "8Gi"

  # AI service is internal — not exposed publicly
  ingress         = "INGRESS_TRAFFIC_INTERNAL_ONLY"

  vpc_connector   = module.networking.vpc_connector_id

  env_vars = {
    ENVIRONMENT      = var.environment
    LOG_LEVEL        = var.environment == "production" ? "WARNING" : "DEBUG"
  }

  secrets = {
    SERVICE_SECRET       = "${local.name_prefix}-ai-service-secret:latest"
    VERTEX_AI_SA_KEY     = "${local.name_prefix}-vertex-sa-key:latest"
    GCS_TRANSCRIPT_BUCKET = "${local.name_prefix}-transcripts-bucket-name:latest"
  }
}

# ── Cloud Run: WebRTC Signaling ───────────────────────────────────────────────

module "signaling_service" {
  source = "./modules/cloud_run"

  project_id      = var.project_id
  region          = var.region
  name            = "${local.name_prefix}-signaling"
  image           = var.signaling_image
  labels          = local.common_labels

  min_instances   = 2
  max_instances   = 30
  concurrency     = 200    # WebSocket connections; high concurrency
  cpu             = "1000m"
  memory          = "512Mi"

  vpc_connector   = module.networking.vpc_connector_id

  env_vars = {
    REDIS_URL   = "redis://${module.cache.host}:${module.cache.port}"
    ENVIRONMENT = var.environment
  }

  secrets = {
    REDIS_PASSWORD   = "${local.name_prefix}-redis-password:latest"
    SIGNALING_SECRET = "${local.name_prefix}-signaling-secret:latest"
  }
}

# ── Cloud Monitoring: Uptime and Alert Policies ───────────────────────────────

resource "google_monitoring_uptime_check_config" "api_health" {
  display_name = "${local.name_prefix} API health check"
  timeout      = "10s"
  period       = "60s"

  http_check {
    path         = "/api/health"
    port         = 443
    use_ssl      = true
    validate_ssl = true
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = "${local.name_prefix}.interviewflow.io"
    }
  }
}

resource "google_monitoring_alert_policy" "api_error_rate" {
  display_name = "${local.name_prefix}: API 5xx error rate > 1%"
  combiner     = "OR"
  labels       = local.common_labels

  conditions {
    display_name = "5xx rate"
    condition_threshold {
      filter          = "resource.type=\"cloud_run_revision\" AND metric.type=\"run.googleapis.com/request_count\" AND metric.labels.response_code_class=\"5xx\""
      duration        = "120s"
      comparison      = "COMPARISON_GT"
      threshold_value = 0.01
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]
}

resource "google_monitoring_notification_channel" "email" {
  display_name = "InterviewFlow on-call email"
  type         = "email"

  labels = {
    email_address = var.alert_email
  }
}
