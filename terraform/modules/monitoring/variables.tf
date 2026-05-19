variable "project_name" {
  type = string
}

variable "env" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "eks_cluster_name" {
  type = string
}

variable "sqs_queue_names" {
  type = map(string)
}

variable "sns_topic_arn" {
  type = string
}

variable "cpu_threshold" {
  type    = number
  default = 80
}

variable "memory_threshold" {
  type    = number
  default = 80
}

variable "sqs_age_threshold" {
  type    = number
  default = 600
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
