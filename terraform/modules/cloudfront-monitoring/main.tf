locals {
  name_prefix   = "${var.project_name}-${var.env}"

  dimensions = {
    DistributionId = var.distribution_id
    Region         = "Global"
  }
}

resource "aws_sns_topic" "alarms" {
  name = "${local.name_prefix}-cloudfront-alarms"
  tags = var.common_tags
}

resource "aws_iam_role" "chatbot" {
  name = "${local.name_prefix}-cloudfront-chatbot-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "chatbot.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "chatbot_readonly" {
  role       = aws_iam_role.chatbot.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_chatbot_slack_channel_configuration" "alerts" {
  configuration_name = "${local.name_prefix}-cloudfront-slack-alerts"
  iam_role_arn       = aws_iam_role.chatbot.arn
  slack_team_id      = var.slack_workspace_id
  slack_channel_id   = var.slack_channel_id
  sns_topic_arns     = [aws_sns_topic.alarms.arn]

  tags = var.common_tags
}

resource "aws_cloudfront_monitoring_subscription" "this" {
  distribution_id = var.distribution_id

  monitoring_subscription {
    realtime_metrics_subscription_config {
      realtime_metrics_subscription_status = "Enabled"
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "error_rate_5xx" {
  alarm_name          = "${local.name_prefix}-cloudfront-5xx-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "5xxErrorRate"
  namespace           = "AWS/CloudFront"
  period              = 300
  statistic           = "Average"
  threshold           = 1
  alarm_description   = "CloudFront 5xx error rate is high"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"
  dimensions          = local.dimensions
  tags                = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "error_rate_4xx" {
  alarm_name          = "${local.name_prefix}-cloudfront-4xx-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "4xxErrorRate"
  namespace           = "AWS/CloudFront"
  period              = 300
  statistic           = "Average"
  threshold           = 10
  alarm_description   = "CloudFront 4xx error rate is high"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"
  dimensions          = local.dimensions
  tags                = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "total_error_rate" {
  alarm_name          = "${local.name_prefix}-cloudfront-total-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "TotalErrorRate"
  namespace           = "AWS/CloudFront"
  period              = 300
  statistic           = "Average"
  threshold           = 10
  alarm_description   = "CloudFront total error rate is high"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"
  dimensions          = local.dimensions
  tags                = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "origin_latency" {
  alarm_name          = "${local.name_prefix}-cloudfront-origin-latency-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "OriginLatency"
  namespace           = "AWS/CloudFront"
  period              = 300
  statistic           = "Average"
  threshold           = 1000
  alarm_description   = "CloudFront origin latency is high"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"
  dimensions          = local.dimensions
  tags                = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "request_spike" {
  alarm_name          = "${local.name_prefix}-cloudfront-request-spike"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Requests"
  namespace           = "AWS/CloudFront"
  period              = 300
  statistic           = "Sum"
  threshold           = 1000
  alarm_description   = "CloudFront request count spike"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  treat_missing_data  = "notBreaching"
  dimensions          = local.dimensions
  tags                = var.common_tags
}
