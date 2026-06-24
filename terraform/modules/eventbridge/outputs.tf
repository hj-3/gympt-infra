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

output "rule_names" {
  description = "EventBridge rule names"
  value = {
    workout_completed     = aws_cloudwatch_event_rule.workout_completed.name
    posture_analyzed      = aws_cloudwatch_event_rule.posture_analyzed.name
    daily_report_schedule = aws_cloudwatch_event_rule.daily_report_schedule.name
  }
}
