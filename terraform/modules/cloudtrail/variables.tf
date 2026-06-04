variable "project_name" {
  type = string
}

variable "env" {
  type = string
}

variable "s3_bucket_name" {
  type = string
}

variable "s3_bucket_policy_id" {
  description = "S3 bucket policy ID for dependency"
  type        = string
  default     = null
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
