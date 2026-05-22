variable "project_name" {
  type = string
}

variable "env" {
  type = string
}

variable "scope" {
  description = "Scope of WAF (REGIONAL or CLOUDFRONT)"
  type        = string
  default     = "REGIONAL"
}

variable "rate_limit" {
  description = "Rate limit per 5 minutes"
  type        = number
  default     = 2000
}

variable "log_retention_days" {
  type    = number
  default = 7
}

variable "aws_region" {
  type = string
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
