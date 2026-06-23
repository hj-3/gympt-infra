variable "project_name" {
  description = "Project name"
  type        = string
}

variable "env" {
  description = "Environment (dev/prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for EKS nodes"
  type        = list(string)
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.35"
}

variable "enable_public_access" {
  description = "Enable public API endpoint access"
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "CIDR blocks allowed to access public endpoint. Must be set explicitly — do not use 0.0.0.0/0 in production."
  type        = list(string)
}

variable "enabled_cluster_log_types" {
  description = "Cluster log types to enable"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

# Node Group
variable "node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 10
}

variable "node_instance_types" {
  description = "Instance types for worker nodes"
  type        = list(string)
  default     = ["t3.large"]
}

variable "node_capacity_type" {
  description = "Capacity type (ON_DEMAND or SPOT)"
  type        = string
  default     = "ON_DEMAND"
}

variable "node_disk_size" {
  description = "Disk size for worker nodes (GB)"
  type        = number
  default     = 50
}

# GPU Node Group
variable "enable_gpu_node_group" {
  description = "Enable GPU node group"
  type        = bool
  default     = false
}

variable "gpu_node_desired_size" {
  description = "Desired number of GPU nodes"
  type        = number
  default     = 0
}

variable "gpu_node_min_size" {
  description = "Minimum number of GPU nodes"
  type        = number
  default     = 0
}

variable "gpu_node_max_size" {
  description = "Maximum number of GPU nodes"
  type        = number
  default     = 3
}

variable "gpu_node_instance_types" {
  description = "GPU instance types"
  type        = list(string)
  default     = ["g4dn.xlarge"]
}

# Karpenter NodePool resource limits (cumulative cap per pool)
variable "karpenter_general_cpu_limit" {
  description = "Karpenter 'general' NodePool 누적 vCPU 상한"
  type        = string
  default     = "100"
}

variable "karpenter_general_memory_limit" {
  description = "Karpenter 'general' NodePool 누적 메모리 상한"
  type        = string
  default     = "200Gi"
}

variable "karpenter_gpu_cpu_limit" {
  description = "Karpenter 'gpu' NodePool 누적 vCPU 상한"
  type        = string
  default     = "32"
}

variable "karpenter_gpu_memory_limit" {
  description = "Karpenter 'gpu' NodePool 누적 메모리 상한"
  type        = string
  default     = "128Gi"
}

variable "karpenter_gpu_count_limit" {
  description = "Karpenter 'gpu' NodePool 누적 nvidia.com/gpu 상한"
  type        = string
  default     = "4"
}

# EKS Addons
variable "vpc_cni_version" {
  description = "VPC CNI addon version"
  type        = string
  default     = "v1.18.5-eksbuild.1"
}

variable "coredns_version" {
  description = "CoreDNS addon version"
  type        = string
  default     = "v1.11.3-eksbuild.2"
}

variable "kube_proxy_version" {
  description = "Kube-proxy addon version"
  type        = string
  default     = "v1.35.0-eksbuild.2"
}

variable "ebs_csi_version" {
  description = "EBS CSI driver addon version"
  type        = string
  default     = "v1.37.0-eksbuild.1"
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}

variable "bootstrap_self_managed_addons" {
  description = "EKS 클러스터 자체 관리 애드온 부트스트랩 여부"
  type        = bool
  default     = false
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}
