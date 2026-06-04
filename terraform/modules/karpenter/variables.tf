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

variable "eks_node_role_name" {
  type = string
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
