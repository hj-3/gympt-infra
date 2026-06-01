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

variable "eks_public_access_cidrs" {
  description = "CIDR blocks allowed to access the EKS public API endpoint. Restrict to office/VPN IPs in production."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "frontend_s3_bucket_name" {
  description = "Name of the existing frontend S3 bucket (created manually). Defaults to gympt-fe-deploy-<account_id>."
  type        = string
  default     = ""
}

variable "cloudfront_distribution_id" {
  description = "ID of the existing CloudFront distribution for the frontend (created manually). Pass via TF_VAR_cloudfront_distribution_id or terraform.tfvars."
  type        = string
}
