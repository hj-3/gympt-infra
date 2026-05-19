variable "project_name" {
  type = string
}

variable "env" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "s3_bucket_arns" {
  type = list(string)
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
