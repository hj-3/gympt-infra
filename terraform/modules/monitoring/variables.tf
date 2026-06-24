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

variable "sqs_dlq_names" {
  type    = map(string)
  default = {}
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

variable "rds_instance_id" {
  type    = string
  default = null
}

variable "lambda_function_names" {
  type    = map(string)
  default = {}
}

variable "dynamodb_table_names" {
  type    = map(string)
  default = {}
}

variable "elasticache_cache_cluster_ids" {
  type    = list(string)
  default = []
}

variable "alb_load_balancer_arn_suffix" {
  type    = string
  default = null
}

variable "alb_target_group_arn_suffixes" {
  type    = map(string)
  default = {}
}

variable "s3_request_metric_buckets" {
  type    = map(string)
  default = {}
}

variable "waf_web_acl_metrics" {
  description = "Map of WAF label to metric dimensions. Scope must be REGIONAL or CLOUDFRONT."
  type = map(object({
    web_acl = string
    region  = string
    rule    = optional(string, "ALL")
  }))
  default = {}
}

variable "kvs_stream_names" {
  type    = map(string)
  default = {}
}

variable "eventbridge_rule_names" {
  type    = map(string)
  default = {}
}

variable "athena_workgroup_names" {
  type    = map(string)
  default = {}
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
