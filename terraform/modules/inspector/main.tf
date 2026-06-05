# SNS Topic
resource "aws_sns_topic" "inspector_alerts" {
  name = "${var.project_name}-${var.env}-inspector-alerts"
  tags = var.common_tags
}

# EventBridge Rule — Inspector finding HIGH/CRITICAL
resource "aws_cloudwatch_event_rule" "inspector_findings" {
  name        = "${var.project_name}-${var.env}-inspector-findings"
  description = "Inspector High/Critical findings to Slack"

  event_pattern = jsonencode({
    source      = ["aws.inspector2"]
    detail-type = ["Inspector2 Finding"]
    detail = {
      severity = ["HIGH", "CRITICAL"]
    }
  })

  tags = var.common_tags
}

resource "aws_cloudwatch_event_target" "inspector_to_sns" {
  rule      = aws_cloudwatch_event_rule.inspector_findings.name
  target_id = "InspectorToSNS"
  arn       = aws_sns_topic.inspector_alerts.arn
}

# SNS → EventBridge 허용 정책
resource "aws_sns_topic_policy" "inspector_alerts" {
  arn = aws_sns_topic.inspector_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventBridge"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.inspector_alerts.arn
      }
    ]
  })
}