variable "project_name" {
  description = "Project name"
  type        = string
}

variable "env" {
  description = "Environment (dev, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}

variable "flow_logs_bucket_arn" {
  description = "S3 bucket ARN for VPC Flow Logs"
  type        = string
  default     = ""
}

variable "enable_cluster_endpoints" {
  description = "ECR/EC2/autoscaling/EKS/ELB VPC endpoints. EKS 노드 있을 때만 필요. false로 설정하면 ~$87/month 절감."
  type        = bool
  default     = true
}

variable "nat_gateway_count" {
  description = "NAT Gateway 수: 0=삭제(비용절감), 1=단일(권장), 2=HA(AZ별 1개)"
  type        = number
  default     = 1
  validation {
    condition     = contains([0, 1, 2], var.nat_gateway_count)
    error_message = "nat_gateway_count는 0, 1, 2 중 하나여야 합니다."
  }
}