variable "project_name" {
  type = string
}

variable "env" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_id" {
  description = "Public subnet ID to place the Boundary EC2 instance"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for Boundary"
  type        = string
  default     = "t3.medium"
}

variable "boundary_version" {
  description = "HashiCorp Boundary version to install"
  type        = string
  default     = "0.17.1"
}

variable "db_password" {
  description = "PostgreSQL password for the boundary database user"
  type        = string
  sensitive   = true
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to reach Boundary ports (9200/9201/9202)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "common_tags" {
  type    = map(string)
  default = {}
}
