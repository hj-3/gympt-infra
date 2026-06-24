locals {
  name_prefix = "${var.project_name}-${var.env}"
}

resource "aws_sns_topic" "alarms" {
  name = "${local.name_prefix}-alarms"
  tags = var.common_tags
}

resource "aws_sns_topic" "security_alarms" {
  count = var.security_slack_channel_id != null ? 1 : 0
  name  = "${local.name_prefix}-security-alarms"
  tags  = var.common_tags
}

resource "aws_sns_topic_policy" "security_alarms" {
  count = var.security_slack_channel_id != null ? 1 : 0
  arn   = aws_sns_topic.security_alarms[0].arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventBridgePublish"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.security_alarms[0].arn
      }
    ]
  })
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alarm_email != null ? 1 : 0
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${local.name_prefix}-dashboard"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/EKS", "node_cpu_utilization", { stat = "Average" }],
            [".", "node_memory_utilization", { stat = "Average" }]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "EKS Node Utilization"
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/RDS", "CPUUtilization", { stat = "Average" }],
            [".", "DatabaseConnections", { stat = "Average" }]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "RDS Metrics"
        }
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "application" {
  name              = "/aws/application/${local.name_prefix}"
  retention_in_days = var.log_retention_days
  tags              = var.common_tags
}

# AWS Chatbot Slack 연동
resource "aws_iam_role" "chatbot" {
  count = var.slack_workspace_id != null ? 1 : 0
  name  = "${local.name_prefix}-chatbot-role"

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
  count      = var.slack_workspace_id != null ? 1 : 0
  role       = aws_iam_role.chatbot[0].name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_chatbot_slack_channel_configuration" "alerts" {
  count              = var.slack_workspace_id != null ? 1 : 0
  configuration_name = "${local.name_prefix}-slack-alerts"
  iam_role_arn       = aws_iam_role.chatbot[0].arn
  slack_team_id      = var.slack_workspace_id
  slack_channel_id   = var.slack_channel_id

  sns_topic_arns = compact([
    aws_sns_topic.alarms.arn,
    var.inspector_sns_topic_arn,
  ])

  tags = var.common_tags
}

resource "aws_chatbot_slack_channel_configuration" "security_alerts" {
  count              = var.slack_workspace_id != null && var.security_slack_channel_id != null ? 1 : 0
  configuration_name = "${local.name_prefix}-security-slack-alerts"
  iam_role_arn       = aws_iam_role.chatbot[0].arn
  slack_team_id      = var.slack_workspace_id
  slack_channel_id   = var.security_slack_channel_id

  sns_topic_arns = [
    aws_sns_topic.security_alarms[0].arn,
  ]

  tags = var.common_tags
}
