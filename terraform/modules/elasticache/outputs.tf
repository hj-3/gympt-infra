output "replication_group_id" {
  value = var.enabled ? aws_elasticache_replication_group.main[0].id : null
}

output "primary_endpoint_address" {
  value = var.enabled ? aws_elasticache_replication_group.main[0].primary_endpoint_address : null
}

output "reader_endpoint_address" {
  value = var.enabled ? aws_elasticache_replication_group.main[0].reader_endpoint_address : null
}

output "port" {
  value = var.enabled ? aws_elasticache_replication_group.main[0].port : null
}

output "security_group_id" {
  value = var.enabled ? aws_security_group.redis[0].id : null
}
