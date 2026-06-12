variable "project_name" {
  type = string
}

variable "env" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "account_id" {
  type = string
}

variable "glue_database_name" {
  description = "Glue catalog database name (gympt_prod_catalog)"
  type        = string
}

variable "athena_results_bucket_id" {
  description = "Athena results S3 bucket name"
  type        = string
}

variable "athena_results_bucket_arn" {
  description = "Athena results S3 bucket ARN"
  type        = string
}

variable "logs_bucket_arn" {
  description = "Central logs S3 bucket ARN (read-only for Athena scanning)"
  type        = string
}

variable "logs_bucket_id" {
  description = "Central logs S3 bucket name"
  type        = string
}

variable "slack_webhook_secret_name" {
  description = "Secrets Manager secret name for Slack incoming webhook URL"
  type        = string
  default     = "gympt/prod/slack/security-webhook-url"
}

variable "slack_webhook_secret_arn" {
  description = "Secrets Manager secret ARN for Slack incoming webhook URL"
  type        = string
}

variable "bedrock_region" {
  description = "AWS region where Bedrock model is invoked"
  type        = string
  default     = "us-west-2"
}

variable "bedrock_model_id" {
  description = "Bedrock foundation model ID"
  type        = string
  default     = "anthropic.claude-3-haiku-20240307-v1:0"
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days"
  type        = number
  default     = 30
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
