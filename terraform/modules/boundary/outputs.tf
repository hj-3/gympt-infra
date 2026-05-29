output "instance_id" {
  value = aws_instance.boundary.id
}

output "public_ip" {
  description = "Boundary EC2 public IP"
  value       = aws_instance.boundary.public_ip
}

output "api_endpoint" {
  description = "Boundary API/UI endpoint"
  value       = "http://${aws_instance.boundary.public_ip}:9200"
}

output "kms_root_key_arn" {
  value = aws_kms_key.boundary_root.arn
}

output "kms_worker_auth_key_arn" {
  value = aws_kms_key.boundary_worker_auth.arn
}

output "kms_recovery_key_arn" {
  value = aws_kms_key.boundary_recovery.arn
}

output "security_group_id" {
  value = aws_security_group.boundary.id
}
