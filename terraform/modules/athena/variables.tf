variable "project_name" {
  type = string
}

variable "env" {
  type = string
}

variable "results_bucket" {
  type = string
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
