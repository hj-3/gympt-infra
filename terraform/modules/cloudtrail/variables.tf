variable "project_name" {
  type = string
}

variable "env" {
  type = string
}

variable "s3_bucket_name" {
  type = string
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
