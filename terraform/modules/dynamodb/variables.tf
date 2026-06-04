variable "project_name" {
  type = string
}

variable "env" {
  type = string
}

variable "enable_point_in_time_recovery" {
  description = "Enable point-in-time recovery"
  type        = bool
  default     = true
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
