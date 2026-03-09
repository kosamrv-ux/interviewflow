variable "project_id"               { type = string }
variable "region"                   { type = string }
variable "name"                     { type = string }
variable "tier"                     { type = string; default = "STANDARD_HA" }
variable "memory_size_gb"           { type = number; default = 4 }
variable "network_id"               { type = string }
variable "labels"                   { type = map(string); default = {} }
variable "replica_count"            { type = number; default = 1 }
variable "auth_enabled"             { type = bool; default = true }
variable "transit_encryption_mode"  { type = string; default = "SERVER_AUTHENTICATION" }
