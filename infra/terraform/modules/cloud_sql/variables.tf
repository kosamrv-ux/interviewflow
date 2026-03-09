variable "project_id"          { type = string }
variable "region"              { type = string }
variable "name"                { type = string }
variable "database_tier"       { type = string; default = "db-standard-4" }
variable "db_name"             { type = string; default = "interviewflow" }
variable "db_user"             { type = string; default = "interviewflow_app" }
variable "network_id"          { type = string }
variable "labels"              { type = map(string); default = {} }
variable "enable_pitr"         { type = bool; default = false }
variable "backup_count"        { type = number; default = 3 }
variable "disk_size_gb"        { type = number; default = 100 }
variable "deletion_protection" { type = bool; default = true }
