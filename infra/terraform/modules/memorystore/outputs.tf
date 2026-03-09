output "host" {
  value     = google_redis_instance.this.host
  sensitive = true
}

output "port" {
  value = google_redis_instance.this.port
}

output "id" {
  value = google_redis_instance.this.id
}
