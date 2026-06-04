variable "project_name" {
  type = string
}

variable "env" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "alarm_email" {
  type    = string
  default = null
}

variable "log_retention_days" {
  type    = number
  default = 14
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
