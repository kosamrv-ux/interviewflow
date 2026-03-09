output "url" {
  description = "HTTPS URL of the Cloud Run service."
  value       = google_cloud_run_v2_service.this.uri
}

output "service_account_email" {
  description = "Email of the dedicated service account."
  value       = google_service_account.run_sa.email
}

output "service_name" {
  description = "Name of the Cloud Run service."
  value       = google_cloud_run_v2_service.this.name
}
