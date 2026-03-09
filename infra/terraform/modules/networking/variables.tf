variable "project_id"   { type = string }
variable "region"       { type = string }
variable "network_name" { type = string }
variable "name_prefix"  { type = string }
variable "labels"       { type = map(string); default = {} }
