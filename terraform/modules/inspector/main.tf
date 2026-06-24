locals {
  name_prefix = "${var.project_name}-${var.env}"
}

# SNS Topic
resource "aws_sns_topic" "inspector_alerts" {
  name = "${local.name_prefix}-inspector-alerts"
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

# Inspector 알림은 AI 보안관제(security-monitor Lambda)가 S3에서 읽어 처리하므로
# SNS/Chatbot 직접 발송 경로 제거

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

# ──────────────────────────────────────────────
# Inspector findings → Kinesis Firehose → S3 (inspector-findings/)
# ──────────────────────────────────────────────

# Firehose가 S3에 쓰기 위한 IAM Role
resource "aws_iam_role" "firehose" {
  name = "${local.name_prefix}-inspector-firehose-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "firehose.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy" "firehose_s3" {
  name = "${local.name_prefix}-inspector-firehose-s3"
  role = aws_iam_role.firehose.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:PutObject",
        "s3:PutObjectAcl",
        "s3:GetBucketLocation",
        "s3:ListBucket"
      ]
      Resource = [
        var.logs_bucket_arn,
        "${var.logs_bucket_arn}/*"
      ]
    }]
  })
}

# Firehose Delivery Stream → S3 inspector-findings/
resource "aws_kinesis_firehose_delivery_stream" "inspector" {
  name        = "${local.name_prefix}-inspector-findings"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn            = aws_iam_role.firehose.arn
    bucket_arn          = var.logs_bucket_arn
    prefix              = "inspector-findings/"
    error_output_prefix = "inspector-findings-errors/"
    buffering_size      = 5
    buffering_interval  = 300
    compression_format  = "GZIP"
  }

  tags = var.common_tags
}

# EventBridge가 Firehose로 보내기 위한 IAM Role
resource "aws_iam_role" "eventbridge_firehose" {
  name = "${local.name_prefix}-inspector-eb-firehose-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy" "eventbridge_firehose" {
  name = "${local.name_prefix}-inspector-eb-firehose"
  role = aws_iam_role.eventbridge_firehose.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["firehose:PutRecord", "firehose:PutRecordBatch"]
      Resource = aws_kinesis_firehose_delivery_stream.inspector.arn
    }]
  })
}

# EventBridge Rule → Firehose target (SNS와 병행)
resource "aws_cloudwatch_event_target" "inspector_to_firehose" {
  rule      = aws_cloudwatch_event_rule.inspector_findings.name
  target_id = "InspectorToFirehose"
  arn       = aws_kinesis_firehose_delivery_stream.inspector.arn
  role_arn  = aws_iam_role.eventbridge_firehose.arn
}

resource "aws_cloudwatch_event_target" "inspector_to_sns" {
  rule      = aws_cloudwatch_event_rule.inspector_findings.name
  target_id = "InspectorToSns"
  arn       = aws_sns_topic.inspector_alerts.arn
}
