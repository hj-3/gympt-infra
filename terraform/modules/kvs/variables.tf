variable "environment" {
  description = "Environment name (dev, prod)"
  type        = string
}

variable "streams" {
  description = "KVS streams configuration"
  type = map(object({
    retention_hours = number
  }))
  default = {
    workout-sessions = {
      retention_hours = 24
    }
  }
}

variable "webrtc_channels" {
  description = "WebRTC signaling channels configuration"
  type = map(object({
    enabled = bool
  }))
  default = {
    live-sessions = {
      enabled = true
    }
  }
}

variable "eks_oidc_provider_arn" {
  description = "EKS OIDC provider ARN for IRSA integration"
  type        = string
}

variable "kvs_namespace" {
  description = "Kubernetes namespace for KVS service accounts"
  type        = string
  default     = "streaming"
}

variable "tags" {
  description = "Common resource tags"
  type        = map(string)
  default     = {}
}
