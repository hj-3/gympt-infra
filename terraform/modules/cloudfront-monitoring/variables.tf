variable "project_name" {
  type = string
}

variable "env" {
  type = string
}

variable "distribution_id" {
  type = string
}

variable "slack_workspace_id" {
  type = string
}

variable "slack_channel_id" {
  type = string
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
