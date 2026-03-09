output "api_url" {
  description = "HTTPS URL of the Phoenix API Cloud Run service."
  value       = module.api_service.url
}

output "ai_service_url" {
  description = "Internal URL of the Python AI scoring Cloud Run service."
  value       = module.ai_service.url
}

output "signaling_url" {
  description = "URL of the WebRTC signaling Cloud Run service."
  value       = module.signaling_service.url
}

output "db_connection_name" {
  description = "Cloud SQL connection name for Cloud Run sidecars."
  value       = module.database.connection_name
}

output "db_private_ip" {
  description = "Private IP of the Cloud SQL primary instance."
  value       = module.database.private_ip
  sensitive   = true
}

output "redis_host" {
  description = "Memorystore Redis host (private IP)."
  value       = module.cache.host
  sensitive   = true
}

output "redis_port" {
  description = "Memorystore Redis port."
  value       = module.cache.port
}

output "artifact_registry_url" {
  description = "Artifact Registry Docker repository URL."
  value       = "us-east1-docker.pkg.dev/${var.project_id}/interviewflow"
}
