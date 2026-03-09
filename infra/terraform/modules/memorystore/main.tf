resource "google_redis_instance" "this" {
  name           = var.name
  tier           = var.tier
  memory_size_gb = var.memory_size_gb
  region         = var.region
  location_id    = "${var.region}-b"

  authorized_network = var.network_id

  redis_version = "REDIS_7_0"

  auth_enabled            = var.auth_enabled
  transit_encryption_mode = var.transit_encryption_mode

  replica_count    = var.replica_count
  read_replicas_mode = var.replica_count > 0 ? "READ_REPLICAS_ENABLED" : "READ_REPLICAS_DISABLED"

  maintenance_policy {
    weekly_maintenance_window {
      day = "SUNDAY"
      start_time {
        hours   = 4
        minutes = 0
        seconds = 0
        nanos   = 0
      }
    }
  }

  labels = var.labels

  lifecycle {
    prevent_destroy = true
  }
}

# Store the auth string in Secret Manager
resource "google_secret_manager_secret" "redis_password" {
  secret_id = "${var.name}-redis-password"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "redis_password" {
  secret      = google_secret_manager_secret.redis_password.id
  secret_data = google_redis_instance.this.auth_string
}
