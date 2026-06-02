variable "project_name" {
  description = "Project name used in resource names"
  type        = string
}

variable "env" {
  description = "Environment name"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "github_repository" {
  description = "GitHub repository allowed to assume this role, in owner/name format"
  type        = string
}

variable "allowed_branches" {
  description = "Git branches allowed to assume this role"
  type        = list(string)
}

variable "create_oidc_provider" {
  description = "Whether this environment should create the shared GitHub Actions OIDC provider"
  type        = bool
  default     = false
}

variable "create_app_role" {
  description = "Whether to create the gympt-app GitHub Actions deployment role"
  type        = bool
  default     = true
}

variable "ecr_repository_arns" {
  description = "ECR repository ARNs that GitHub Actions may push to"
  type        = list(string)
  default     = []
}

variable "frontend_bucket_arn" {
  description = "Frontend deployment bucket ARN"
  type        = string
  default     = null
}

variable "lambda_artifacts_bucket_arn" {
  description = "Lambda artifacts bucket ARN"
  type        = string
  default     = null
}

variable "cloudfront_distribution_arns" {
  description = "CloudFront distribution ARNs that GitHub Actions may invalidate"
  type        = list(string)
  default     = []
}

variable "common_tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
