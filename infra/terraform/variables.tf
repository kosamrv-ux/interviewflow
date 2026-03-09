variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "Primary GCP region for all resources."
  type        = string
  default     = "us-east1"
}

variable "environment" {
  description = "Deployment environment: staging | production."
  type        = string
  validation {
    condition     = contains(["staging", "production"], var.environment)
    error_message = "environment must be 'staging' or 'production'."
  }
}

variable "app_image" {
  description = "Docker image URI for the Phoenix API service (Artifact Registry)."
  type        = string
}

variable "ai_image" {
  description = "Docker image URI for the Python AI scoring service."
  type        = string
}

variable "signaling_image" {
  description = "Docker image URI for the WebRTC signaling service."
  type        = string
}

variable "db_tier" {
  description = "Cloud SQL machine type."
  type        = string
  default     = "db-standard-4"
}

variable "db_name" {
  description = "PostgreSQL database name."
  type        = string
  default     = "interviewflow"
}

variable "db_user" {
  description = "PostgreSQL user name (password managed via Secret Manager)."
  type        = string
  default     = "interviewflow_app"
}

variable "redis_tier" {
  description = "Memorystore Redis service tier: BASIC | STANDARD_HA."
  type        = string
  default     = "STANDARD_HA"
}

variable "redis_memory_gb" {
  description = "Memorystore instance memory size in GB."
  type        = number
  default     = 4
}

variable "api_min_instances" {
  description = "Cloud Run minimum instance count (prevents cold starts)."
  type        = number
  default     = 2
}

variable "api_max_instances" {
  description = "Cloud Run maximum instance count."
  type        = number
  default     = 50
}

variable "api_concurrency" {
  description = "Cloud Run max concurrent requests per instance."
  type        = number
  default     = 80
}

variable "ai_min_instances" {
  description = "AI service Cloud Run minimum instances."
  type        = number
  default     = 1
}

variable "ai_max_instances" {
  description = "AI service Cloud Run maximum instances."
  type        = number
  default     = 20
}

variable "allowed_origins" {
  description = "CORS allowed origins list for the API service."
  type        = list(string)
  default     = []
}

variable "alert_email" {
  description = "Email address for Cloud Monitoring alert notifications."
  type        = string
}

variable "vpc_network" {
  description = "VPC network name for private service connections."
  type        = string
  default     = "interviewflow-vpc"
}
