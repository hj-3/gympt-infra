output "event_bus_arn" {
  description = "EventBridge event bus ARN"
  value       = aws_cloudwatch_event_bus.main.arn
}

output "event_bus_name" {
  description = "EventBridge event bus name"
  value       = aws_cloudwatch_event_bus.main.name
}

output "archive_arn" {
  description = "EventBridge archive ARN"
  value       = aws_cloudwatch_event_archive.main.arn
}
