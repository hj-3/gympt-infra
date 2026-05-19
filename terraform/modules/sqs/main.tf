locals {
  name_prefix = "${var.project_name}-${var.env}"

  queues = [
    "report-generation",
    "posture-event",
    "thumbnail-generation",
    "wearable-sync",
    "recommendation-update",
    "notification",
    "export"
  ]
}

# Main Queues
resource "aws_sqs_queue" "main" {
  for_each = toset(local.queues)

  name                       = "${local.name_prefix}-${each.value}-queue"
  visibility_timeout_seconds = 300
  message_retention_seconds  = 1209600  # 14 days
  delay_seconds              = 0
  receive_wait_time_seconds  = 10  # Long polling
  
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[each.value].arn
    maxReceiveCount     = 3
  })

  tags = merge(
    var.common_tags,
    {
      Name = "${local.name_prefix}-${each.value}-queue"
      Type = "main"
    }
  )
}

# Dead Letter Queues
resource "aws_sqs_queue" "dlq" {
  for_each = toset(local.queues)

  name                      = "${local.name_prefix}-${each.value}-dlq"
  message_retention_seconds = 1209600  # 14 days

  tags = merge(
    var.common_tags,
    {
      Name = "${local.name_prefix}-${each.value}-dlq"
      Type = "dlq"
    }
  )
}

# CloudWatch Alarms for DLQs
resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  for_each = aws_sqs_queue.dlq

  alarm_name          = "${each.value.name}-messages"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "Alert when messages appear in DLQ"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = each.value.name
  }

  tags = var.common_tags
}
