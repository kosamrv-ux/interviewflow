variable "project_id"        { type = string }
variable "region"            { type = string }
variable "name"              { type = string }
variable "image"             { type = string }
variable "labels"            { type = map(string); default = {} }
variable "min_instances"     { type = number; default = 1 }
variable "max_instances"     { type = number; default = 10 }
variable "concurrency"       { type = number; default = 80 }
variable "cpu"               { type = string; default = "1000m" }
variable "memory"            { type = string; default = "512Mi" }
variable "ingress"           { type = string; default = "INGRESS_TRAFFIC_ALL" }
variable "vpc_connector"     { type = string; default = "" }
variable "cloudsql_instances"{ type = list(string); default = [] }
variable "env_vars"          { type = map(string); default = {} }
variable "secrets"           { type = map(string); default = {} }
variable "liveness_probe"    { type = any; default = null }
variable "startup_probe"     { type = any; default = null }
