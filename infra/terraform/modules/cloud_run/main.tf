resource "google_cloud_run_v2_service" "this" {
  name     = var.name
  location = var.region
  ingress  = var.ingress

  labels = var.labels

  template {
    labels = var.labels

    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    containers {
      image = var.image

      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
        cpu_idle          = true
        startup_cpu_boost = true
      }

      # Plain env vars
      dynamic "env" {
        for_each = var.env_vars
        content {
          name  = env.key
          value = env.value
        }
      }

      # Secret-backed env vars from Secret Manager
      dynamic "env" {
        for_each = var.secrets
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = split(":", env.value)[0]
              version = split(":", env.value)[1]
            }
          }
        }
      }

      # Liveness probe
      dynamic "liveness_probe" {
        for_each = var.liveness_probe != null ? [var.liveness_probe] : []
        content {
          initial_delay_seconds = lookup(liveness_probe.value, "initial_delay_seconds", 10)
          period_seconds        = lookup(liveness_probe.value, "period_seconds", 15)
          timeout_seconds       = lookup(liveness_probe.value, "timeout_seconds", 5)
          failure_threshold     = lookup(liveness_probe.value, "failure_threshold", 3)

          http_get {
            path = liveness_probe.value.http_get.path
          }
        }
      }

      # Startup probe
      dynamic "startup_probe" {
        for_each = var.startup_probe != null ? [var.startup_probe] : []
        content {
          failure_threshold = lookup(startup_probe.value, "failure_threshold", 6)
          period_seconds    = lookup(startup_probe.value, "period_seconds", 10)

          http_get {
            path = startup_probe.value.http_get.path
          }
        }
      }
    }

    max_instance_request_concurrency = var.concurrency

    # VPC connector for private service access
    vpc_access {
      connector = var.vpc_connector
      egress    = "PRIVATE_RANGES_ONLY"
    }

    # Cloud SQL connections (sidecar proxy)
    dynamic "volumes" {
      for_each = length(var.cloudsql_instances) > 0 ? [true] : []
      content {
        name = "cloudsql"
        cloud_sql_instance {
          instances = var.cloudsql_instances
        }
      }
    }

    service_account = google_service_account.run_sa.email
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  lifecycle {
    ignore_changes = [
      # Allow CI/CD to update image without Terraform re-planning
      template[0].containers[0].image
    ]
  }
}

# Dedicated service account per service (least privilege)
resource "google_service_account" "run_sa" {
  account_id   = "${var.name}-sa"
  display_name = "Cloud Run SA for ${var.name}"
}

# Allow Secret Manager access
resource "google_project_iam_member" "secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.run_sa.email}"
}

# Public HTTP access (overridden to internal-only via var.ingress on AI svc)
resource "google_cloud_run_v2_service_iam_member" "public" {
  count    = var.ingress == "INGRESS_TRAFFIC_ALL" ? 1 : 0
  location = var.region
  name     = google_cloud_run_v2_service.this.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
