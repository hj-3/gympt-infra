variable "project_name" {
  description = "Project name"
  type        = string
}

variable "env" {
  description = "Environment"
  type        = string
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
}

variable "create_frontend" {
  description = "Create frontend S3 bucket (set false if already exists)"
  type        = bool
  default     = true
}

variable "common_tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
