variable "project_name" {
  type = string
}

variable "env" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "oidc_provider_url" {
  type = string
}

variable "pod_service_accounts" {
  description = "Map of service account name to namespace and service account"
  type = map(object({
    namespace       = string
    service_account = string
  }))
  default = {
    backend-api = {
      namespace       = "backend-api"
      service_account = "backend-api"
    }
    agent-service = {
      namespace       = "agent-service"
      service_account = "agent-service"
    }
    posture-analysis-service = {
      namespace       = "posture-analysis"
      service_account = "posture-analysis-service"
    }
    report-service = {
      namespace       = "report-service"
      service_account = "report-service"
    }
    generic-worker = {
      namespace       = "workers"
      service_account = "generic-worker"
    }
  }
}

variable "s3_bucket_arns" {
  type = list(string)
}

variable "dynamodb_table_arns" {
  type = list(string)
}

variable "common_tags" {
  type    = map(string)
  default = {}
}

variable "aws_region" {
  type        = string
  description = "AWS region for resources"
  default     = "ap-northeast-2"
}

variable "bedrock_region" {
  type        = string
  description = "AWS region for Bedrock service"
  default     = "us-west-2"
}
