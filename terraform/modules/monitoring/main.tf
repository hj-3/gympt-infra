locals {
  name_prefix = "${var.project_name}-${var.env}"
}

resource "aws_cloudwatch_metric_alarm" "eks_cpu_high" {
  alarm_name          = "${local.name_prefix}-eks-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "node_cpu_utilization"
  namespace           = "ContainerInsights"
  period              = "300"
  statistic           = "Average"
  threshold           = var.cpu_threshold
  alarm_description   = "EKS CPU utilization high"
  alarm_actions       = [var.sns_topic_arn]

  dimensions = {
    ClusterName = var.eks_cluster_name
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "eks_memory_high" {
  alarm_name          = "${local.name_prefix}-eks-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "node_memory_utilization"
  namespace           = "ContainerInsights"
  period              = "300"
  statistic           = "Average"
  threshold           = var.memory_threshold
  alarm_description   = "EKS memory utilization high"
  alarm_actions       = [var.sns_topic_arn]

  dimensions = {
    ClusterName = var.eks_cluster_name
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "sqs_age_high" {
  for_each            = var.sqs_queue_names
  alarm_name          = "${local.name_prefix}-${each.key}-message-age-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ApproximateAgeOfOldestMessage"
  namespace           = "AWS/SQS"
  period              = "300"
  statistic           = "Maximum"
  threshold           = var.sqs_age_threshold
  alarm_description   = "SQS message age too high"
  alarm_actions       = [var.sns_topic_arn]

  dimensions = {
    QueueName = each.value
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_dashboard" "monitoring" {
  dashboard_name = "${local.name_prefix}-monitoring"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Lambda", "Invocations", { stat = "Sum" }],
            [".", "Errors", { stat = "Sum" }],
            [".", "Duration", { stat = "Average" }]
          ]
          period = 300
          region = var.aws_region
          title  = "Lambda Metrics"
        }
      },
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/SQS", "NumberOfMessagesSent", { stat = "Sum" }],
            [".", "NumberOfMessagesReceived", { stat = "Sum" }],
            [".", "ApproximateAgeOfOldestMessage", { stat = "Maximum" }]
          ]
          period = 300
          region = var.aws_region
          title  = "SQS Metrics"
        }
      }
    ]
  })
}
