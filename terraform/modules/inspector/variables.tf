variable "project_name" { type = string }
variable "env"          { type = string }
variable "common_tags"  { type = map(string) }

variable "logs_bucket_arn" {
  description = "ARN of the central logs S3 bucket for Inspector findings delivery"
  type        = string
}