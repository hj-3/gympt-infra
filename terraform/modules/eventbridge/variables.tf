variable "project_name" {
  description = "Project name"
  type        = string
}

variable "env" {
  description = "Environment (dev/prod)"
  type        = string
}

variable "report_queue_arn" {
  description = "Report generation SQS queue ARN"
  type        = string
}

variable "recommendation_queue_arn" {
  description = "Recommendation update SQS queue ARN"
  type        = string
}

variable "notification_queue_arn" {
  description = "Notification SQS queue ARN"
  type        = string
}

variable "wearable_sync_queue_arn" {
  description = "Wearable sync SQS queue ARN"
  type        = string
}

variable "report_generator_lambda_arn" {
  description = "Report generator Lambda ARN"
  type        = string
}

variable "report_generator_lambda_name" {
  description = "Report generator Lambda name"
  type        = string
}

variable "recommendation_lambda_arn" {
  description = "Recommendation Lambda ARN"
  type        = string
}

variable "recommendation_lambda_name" {
  description = "Recommendation Lambda name"
  type        = string
}

variable "archive_retention_days" {
  description = "Event archive retention in days"
  type        = number
  default     = 30
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
