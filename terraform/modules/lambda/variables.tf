variable "project_name" {
  description = "Project name"
  type        = string
}

variable "env" {
  description = "Environment (dev/prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "lambda_artifact_bucket" {
  description = "S3 bucket for Lambda deployment packages"
  type        = string
}

variable "dynamodb_table_arns" {
  description = "DynamoDB table ARNs for Lambda access"
  type        = list(string)
  default     = []
}

variable "s3_bucket_arns" {
  description = "S3 bucket ARNs for Lambda access"
  type        = list(string)
  default     = []
}

variable "sqs_queue_arns" {
  description = "SQS queue ARNs for Lambda access"
  type        = list(string)
  default     = []
}

variable "secrets_manager_arns" {
  description = "Secrets Manager ARNs for Lambda access"
  type        = list(string)
  default     = []
}

variable "dlq_arn" {
  description = "Dead letter queue ARN"
  type        = string
  default     = null
}

variable "log_level" {
  description = "Log level for Lambda functions"
  type        = string
  default     = "INFO"
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days"
  type        = number
  default     = 14
}

variable "environment_variables" {
  description = "Additional environment variables"
  type        = map(string)
  default     = {}
}

# VPC Configuration
variable "vpc_config_enabled" {
  description = "Enable VPC configuration for Lambda"
  type        = bool
  default     = false
}

variable "vpc_subnet_ids" {
  description = "VPC subnet IDs for Lambda"
  type        = list(string)
  default     = []
}

variable "vpc_security_group_ids" {
  description = "VPC security group IDs for Lambda"
  type        = list(string)
  default     = []
}

# Performance Configuration
variable "reserved_concurrent_executions" {
  description = "Reserved concurrent executions (-1 for unreserved)"
  type        = number
  default     = -1
}

variable "xray_tracing_enabled" {
  description = "Enable AWS X-Ray tracing"
  type        = bool
  default     = true
}

# SQS Event Sources
variable "sqs_event_sources" {
  description = "Map of SQS event sources for Lambda functions"
  type = map(object({
    queue_arn       = string
    batch_size      = number
    max_concurrency = number
  }))
  default = {}
}

# CloudWatch Alarms
variable "error_alarm_threshold" {
  description = "Error alarm threshold"
  type        = number
  default     = 5
}

variable "alarm_actions" {
  description = "SNS topic ARNs for alarms"
  type        = list(string)
  default     = []
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
