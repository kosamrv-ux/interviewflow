resource "google_sql_database_instance" "primary" {
  name             = var.name
  database_version = "POSTGRES_15"
  region           = var.region

  deletion_protection = var.deletion_protection

  settings {
    tier              = var.database_tier
    availability_type = var.enable_pitr ? "REGIONAL" : "ZONAL"
    disk_type         = "PD_SSD"
    disk_size         = var.disk_size_gb
    disk_autoresize   = true

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = var.enable_pitr
      start_time                     = "03:00"
      backup_retention_settings {
        retained_backups = var.backup_count
        retention_unit   = "COUNT"
      }
      transaction_log_retention_days = var.enable_pitr ? 7 : 1
    }

    maintenance_window {
      day          = 7  # Sunday
      hour         = 4  # 04:00 UTC
      update_track = "stable"
    }

    ip_configuration {
      ipv4_enabled    = false  # No public IP
      private_network = var.network_id
      ssl_mode        = "ENCRYPTED_ONLY"
    }

    insights_config {
      query_insights_enabled  = true
      query_string_length     = 1024
      record_application_tags = true
      record_client_address   = false  # Privacy
    }

    database_flags {
      name  = "max_connections"
      value = "300"
    }

    database_flags {
      name  = "shared_buffers"
      value = "256000"  # 256 MB
    }

    database_flags {
      name  = "log_min_duration_statement"
      value = "1000"  # Log queries > 1 s
    }

    user_labels = var.labels
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_sql_database" "app" {
  name     = var.db_name
  instance = google_sql_database_instance.primary.name
}

resource "google_sql_user" "app" {
  name     = var.db_user
  instance = google_sql_database_instance.primary.name
  password = data.google_secret_manager_secret_version.db_password.secret_data
}

data "google_secret_manager_secret_version" "db_password" {
  secret = "${var.name}-db-password"
}
