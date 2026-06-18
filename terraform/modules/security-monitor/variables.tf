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
  default     = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
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

# ── 운영 파라미터 (Lambda 환경변수 — 콘솔에서 직접 수정 가능) ────────────────
variable "vpc_flow_reject_threshold" {
  description = "VPC Flow REJECT 건수 임계값 (이 값 이상이면 감지)"
  type        = number
  default     = 10
}

variable "vpc_flow_window_minutes" {
  description = "VPC Flow 스캔 윈도우 (분) — 최근 N분 데이터만 스캔"
  type        = number
  default     = 30
}

variable "waf_block_threshold" {
  description = "WAF 동일 IP 차단 건수 임계값"
  type        = number
  default     = 5
}

variable "s3_error_threshold" {
  description = "S3 에러 응답 건수 임계값"
  type        = number
  default     = 5
}

variable "alb_error_threshold" {
  description = "ALB 4xx/5xx 에러 건수 임계값"
  type        = number
  default     = 10
}

variable "schedule_min_level" {
  description = "정기 스캔 알람 최소 위협 레벨 (CRITICAL / HIGH / MEDIUM / LOW)"
  type        = string
  default     = "HIGH"
}
