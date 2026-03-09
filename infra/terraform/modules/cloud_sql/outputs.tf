output "connection_name" {
  value = google_sql_database_instance.primary.connection_name
}

output "private_ip" {
  value     = google_sql_database_instance.primary.private_ip_address
  sensitive = true
}

output "instance_name" {
  value = google_sql_database_instance.primary.name
}
