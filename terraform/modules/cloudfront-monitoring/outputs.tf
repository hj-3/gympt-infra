output "alarm_arns" {
  value = {
    error_rate_5xx   = aws_cloudwatch_metric_alarm.error_rate_5xx.arn
    error_rate_4xx   = aws_cloudwatch_metric_alarm.error_rate_4xx.arn
    total_error_rate = aws_cloudwatch_metric_alarm.total_error_rate.arn
    origin_latency   = aws_cloudwatch_metric_alarm.origin_latency.arn
    request_spike    = aws_cloudwatch_metric_alarm.request_spike.arn
  }
}

output "sns_topic_arn" {
  value = aws_sns_topic.alarms.arn
}
