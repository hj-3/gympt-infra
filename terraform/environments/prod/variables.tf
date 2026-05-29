variable "rds_master_password" {
  description = "RDS master password"
  type        = string
  sensitive   = true
}

variable "redis_auth_token" {
  description = "Redis AUTH token"
  type        = string
  sensitive   = true
}

variable "alarm_email" {
  description = "Email for CloudWatch alarms"
  type        = string
  default     = null
}

variable "boundary_db_password" {
  description = "PostgreSQL password for Boundary database user. Pass via TF_VAR_boundary_db_password."
  type        = string
  sensitive   = true
}
