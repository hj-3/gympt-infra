output "sns_topic_arn" {
  value = aws_sns_topic.alarms.arn
}

output "security_sns_topic_arn" {
  value = try(aws_sns_topic.security_alarms[0].arn, null)
}

output "dashboard_name" {
  value = aws_cloudwatch_dashboard.main.dashboard_name
}
