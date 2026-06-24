locals {
  name_prefix = "${var.project_name}-${var.env}"

  alarm_actions = [var.sns_topic_arn]

  alb_dimensions = var.alb_load_balancer_arn_suffix == null ? {} : {
    LoadBalancer = var.alb_load_balancer_arn_suffix
  }
}

# EKS / nodes
resource "aws_cloudwatch_metric_alarm" "eks_cpu_high" {
  alarm_name          = "${local.name_prefix}-eks-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "node_cpu_utilization"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Average"
  threshold           = var.cpu_threshold
  alarm_description   = "EKS node CPU utilization high"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.eks_cluster_name
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "eks_memory_high" {
  alarm_name          = "${local.name_prefix}-eks-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "node_memory_utilization"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Average"
  threshold           = var.memory_threshold
  alarm_description   = "EKS node memory utilization high"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.eks_cluster_name
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "eks_node_filesystem_high" {
  alarm_name          = "${local.name_prefix}-eks-node-filesystem-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "node_filesystem_utilization"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "EKS node filesystem utilization high"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.eks_cluster_name
  }

  tags = var.common_tags
}

# RDS
resource "aws_cloudwatch_metric_alarm" "rds_connections_high" {
  count               = var.rds_instance_id != null ? 1 : 0
  alarm_name          = "${local.name_prefix}-rds-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "RDS database connections are high"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_id
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "rds_read_latency_high" {
  count               = var.rds_instance_id != null ? 1 : 0
  alarm_name          = "${local.name_prefix}-rds-read-latency-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ReadLatency"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 0.2
  alarm_description   = "RDS read latency is high"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_id
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "rds_write_latency_high" {
  count               = var.rds_instance_id != null ? 1 : 0
  alarm_name          = "${local.name_prefix}-rds-write-latency-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "WriteLatency"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 0.2
  alarm_description   = "RDS write latency is high"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_id
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "rds_read_iops_high" {
  count               = var.rds_instance_id != null ? 1 : 0
  alarm_name          = "${local.name_prefix}-rds-read-iops-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ReadIOPS"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 500
  alarm_description   = "RDS read IOPS are high"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_id
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "rds_write_iops_high" {
  count               = var.rds_instance_id != null ? 1 : 0
  alarm_name          = "${local.name_prefix}-rds-write-iops-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "WriteIOPS"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 500
  alarm_description   = "RDS write IOPS are high"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_id
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "rds_deadlocks" {
  count               = var.rds_instance_id != null ? 1 : 0
  alarm_name          = "${local.name_prefix}-rds-deadlocks"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Deadlocks"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "RDS deadlocks detected"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_id
  }

  tags = var.common_tags
}

# Lambda
resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  for_each            = var.lambda_function_names
  alarm_name          = "${local.name_prefix}-${each.key}-lambda-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Lambda throttles detected for ${each.key}"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = each.value
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_concurrent_executions" {
  for_each            = var.lambda_function_names
  alarm_name          = "${local.name_prefix}-${each.key}-lambda-concurrency-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ConcurrentExecutions"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Maximum"
  threshold           = 20
  alarm_description   = "Lambda concurrent executions are high for ${each.key}"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = each.value
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_async_event_age" {
  for_each            = var.lambda_function_names
  alarm_name          = "${local.name_prefix}-${each.key}-lambda-async-event-age-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "AsyncEventAge"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Maximum"
  threshold           = 60000
  alarm_description   = "Lambda async event age is high for ${each.key}"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = each.value
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_dead_letter_errors" {
  for_each            = var.lambda_function_names
  alarm_name          = "${local.name_prefix}-${each.key}-lambda-dlq-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "DeadLetterErrors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Lambda DLQ delivery errors detected for ${each.key}"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = each.value
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "lambda_destination_delivery_failures" {
  for_each            = var.lambda_function_names
  alarm_name          = "${local.name_prefix}-${each.key}-lambda-destination-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "DestinationDeliveryFailures"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Lambda destination delivery failures detected for ${each.key}"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = each.value
  }

  tags = var.common_tags
}

# SQS
resource "aws_cloudwatch_metric_alarm" "sqs_age_high" {
  for_each            = var.sqs_queue_names
  alarm_name          = "${local.name_prefix}-${each.key}-message-age-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateAgeOfOldestMessage"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Maximum"
  threshold           = var.sqs_age_threshold
  alarm_description   = "SQS message age too high for ${each.key}"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = each.value
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "sqs_visible_messages" {
  for_each            = var.sqs_queue_names
  alarm_name          = "${local.name_prefix}-${each.key}-visible-messages-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Maximum"
  threshold           = 10
  alarm_description   = "SQS visible messages are high for ${each.key}"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = each.value
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "sqs_not_visible_messages" {
  for_each            = var.sqs_queue_names
  alarm_name          = "${local.name_prefix}-${each.key}-inflight-messages-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ApproximateNumberOfMessagesNotVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Maximum"
  threshold           = 10
  alarm_description   = "SQS in-flight messages are high for ${each.key}"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = each.value
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "sqs_dlq_messages" {
  for_each            = var.sqs_dlq_names
  alarm_name          = "${local.name_prefix}-${each.key}-dlq-messages"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "SQS DLQ has messages for ${each.key}"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = each.value
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "sqs_receive_delete_imbalance" {
  for_each            = var.sqs_queue_names
  alarm_name          = "${local.name_prefix}-${each.key}-receive-delete-imbalance"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 10
  alarm_description   = "SQS receive/delete imbalance is high for ${each.key}"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "imbalance"
    expression  = "IF(received > deleted, received - deleted, 0)"
    label       = "ReceiveDeleteImbalance"
    return_data = true
  }

  metric_query {
    id = "received"

    metric {
      metric_name = "NumberOfMessagesReceived"
      namespace   = "AWS/SQS"
      period      = 300
      stat        = "Sum"

      dimensions = {
        QueueName = each.value
      }
    }
  }

  metric_query {
    id = "deleted"

    metric {
      metric_name = "NumberOfMessagesDeleted"
      namespace   = "AWS/SQS"
      period      = 300
      stat        = "Sum"

      dimensions = {
        QueueName = each.value
      }
    }
  }

  tags = var.common_tags
}

# DynamoDB
resource "aws_cloudwatch_metric_alarm" "dynamodb_system_errors" {
  for_each            = var.dynamodb_table_names
  alarm_name          = "${local.name_prefix}-${each.key}-dynamodb-system-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "SystemErrors"
  namespace           = "AWS/DynamoDB"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "DynamoDB system errors detected for ${each.key}"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    TableName = each.value
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "dynamodb_user_errors" {
  for_each            = var.dynamodb_table_names
  alarm_name          = "${local.name_prefix}-${each.key}-dynamodb-user-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UserErrors"
  namespace           = "AWS/DynamoDB"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "DynamoDB user errors are high for ${each.key}"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    TableName = each.value
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "dynamodb_read_throttles" {
  for_each            = var.dynamodb_table_names
  alarm_name          = "${local.name_prefix}-${each.key}-dynamodb-read-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ReadThrottleEvents"
  namespace           = "AWS/DynamoDB"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "DynamoDB read throttles detected for ${each.key}"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    TableName = each.value
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "dynamodb_write_throttles" {
  for_each            = var.dynamodb_table_names
  alarm_name          = "${local.name_prefix}-${each.key}-dynamodb-write-throttles"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "WriteThrottleEvents"
  namespace           = "AWS/DynamoDB"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "DynamoDB write throttles detected for ${each.key}"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    TableName = each.value
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "dynamodb_transaction_conflicts" {
  for_each            = var.dynamodb_table_names
  alarm_name          = "${local.name_prefix}-${each.key}-dynamodb-transaction-conflicts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "TransactionConflict"
  namespace           = "AWS/DynamoDB"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "DynamoDB transaction conflicts detected for ${each.key}"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    TableName = each.value
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "dynamodb_consumed_read_spike" {
  for_each            = var.dynamodb_table_names
  alarm_name          = "${local.name_prefix}-${each.key}-dynamodb-consumed-read-spike"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ConsumedReadCapacityUnits"
  namespace           = "AWS/DynamoDB"
  period              = 300
  statistic           = "Sum"
  threshold           = 1000
  alarm_description   = "DynamoDB consumed read capacity spike for ${each.key}"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    TableName = each.value
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "dynamodb_consumed_write_spike" {
  for_each            = var.dynamodb_table_names
  alarm_name          = "${local.name_prefix}-${each.key}-dynamodb-consumed-write-spike"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ConsumedWriteCapacityUnits"
  namespace           = "AWS/DynamoDB"
  period              = 300
  statistic           = "Sum"
  threshold           = 500
  alarm_description   = "DynamoDB consumed write capacity spike for ${each.key}"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    TableName = each.value
  }

  tags = var.common_tags
}

# ElastiCache
resource "aws_cloudwatch_metric_alarm" "elasticache_engine_cpu_high" {
  for_each            = toset(var.elasticache_cache_cluster_ids)
  alarm_name          = "${local.name_prefix}-${each.value}-redis-engine-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "EngineCPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Average"
  threshold           = 75
  alarm_description   = "Redis engine CPU utilization is high for ${each.value}"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    CacheClusterId = each.value
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "elasticache_swap_high" {
  for_each            = toset(var.elasticache_cache_cluster_ids)
  alarm_name          = "${local.name_prefix}-${each.value}-redis-swap-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "SwapUsage"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Average"
  threshold           = 52428800
  alarm_description   = "Redis swap usage is high for ${each.value}"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    CacheClusterId = each.value
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "elasticache_replication_lag_high" {
  for_each            = toset(var.elasticache_cache_cluster_ids)
  alarm_name          = "${local.name_prefix}-${each.value}-redis-replication-lag-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ReplicationLag"
  namespace           = "AWS/ElastiCache"
  period              = 300
  statistic           = "Maximum"
  threshold           = 5
  alarm_description   = "Redis replication lag is high for ${each.value}"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    CacheClusterId = each.value
  }

  tags = var.common_tags
}

# ALB
resource "aws_cloudwatch_metric_alarm" "alb_target_5xx" {
  count               = var.alb_load_balancer_arn_suffix != null ? 1 : 0
  alarm_name          = "${local.name_prefix}-alb-target-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "ALB target 5xx responses detected"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"
  dimensions          = local.alb_dimensions
  tags                = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "alb_elb_5xx" {
  count               = var.alb_load_balancer_arn_suffix != null ? 1 : 0
  alarm_name          = "${local.name_prefix}-alb-elb-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "ALB 5xx responses detected"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"
  dimensions          = local.alb_dimensions
  tags                = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "alb_target_response_time" {
  count               = var.alb_load_balancer_arn_suffix != null ? 1 : 0
  alarm_name          = "${local.name_prefix}-alb-target-response-time-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Average"
  threshold           = 2
  alarm_description   = "ALB target response time is high"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"
  dimensions          = local.alb_dimensions
  tags                = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "alb_rejected_connection_count" {
  count               = var.alb_load_balancer_arn_suffix != null ? 1 : 0
  alarm_name          = "${local.name_prefix}-alb-rejected-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "RejectedConnectionCount"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "ALB rejected connections detected"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"
  dimensions          = local.alb_dimensions
  tags                = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "alb_tls_negotiation_errors" {
  count               = var.alb_load_balancer_arn_suffix != null ? 1 : 0
  alarm_name          = "${local.name_prefix}-alb-tls-negotiation-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ClientTLSNegotiationErrorCount"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "ALB client TLS negotiation errors detected"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"
  dimensions          = local.alb_dimensions
  tags                = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
  for_each            = var.alb_load_balancer_arn_suffix != null ? var.alb_target_group_arn_suffixes : {}
  alarm_name          = "${local.name_prefix}-${each.key}-alb-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "ALB target group unhealthy hosts detected for ${each.key}"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.alb_load_balancer_arn_suffix
    TargetGroup  = each.value
  }

  tags = var.common_tags
}

# S3
resource "aws_cloudwatch_metric_alarm" "s3_4xx_errors" {
  for_each            = var.s3_request_metric_buckets
  alarm_name          = "${local.name_prefix}-${each.key}-s3-4xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "4xxErrors"
  namespace           = "AWS/S3"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "S3 4xx request errors are high for ${each.key}"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    BucketName = each.value
    FilterId   = "EntireBucket"
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "s3_5xx_errors" {
  for_each            = var.s3_request_metric_buckets
  alarm_name          = "${local.name_prefix}-${each.key}-s3-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "5xxErrors"
  namespace           = "AWS/S3"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "S3 5xx request errors detected for ${each.key}"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    BucketName = each.value
    FilterId   = "EntireBucket"
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "s3_first_byte_latency" {
  for_each            = var.s3_request_metric_buckets
  alarm_name          = "${local.name_prefix}-${each.key}-s3-first-byte-latency-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "FirstByteLatency"
  namespace           = "AWS/S3"
  period              = 300
  statistic           = "Average"
  threshold           = 1000
  alarm_description   = "S3 first byte latency is high for ${each.key}"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    BucketName = each.value
    FilterId   = "EntireBucket"
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "s3_request_spike" {
  for_each            = var.s3_request_metric_buckets
  alarm_name          = "${local.name_prefix}-${each.key}-s3-request-spike"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "AllRequests"
  namespace           = "AWS/S3"
  period              = 300
  statistic           = "Sum"
  threshold           = 1000
  alarm_description   = "S3 request count spike for ${each.key}"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    BucketName = each.value
    FilterId   = "EntireBucket"
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "s3_bucket_size_high" {
  for_each            = var.s3_request_metric_buckets
  alarm_name          = "${local.name_prefix}-${each.key}-s3-bucket-size-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "BucketSizeBytes"
  namespace           = "AWS/S3"
  period              = 86400
  statistic           = "Average"
  threshold           = 107374182400
  alarm_description   = "S3 bucket size is high for ${each.key}"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    BucketName  = each.value
    StorageType = "StandardStorage"
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "s3_object_count_high" {
  for_each            = var.s3_request_metric_buckets
  alarm_name          = "${local.name_prefix}-${each.key}-s3-object-count-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "NumberOfObjects"
  namespace           = "AWS/S3"
  period              = 86400
  statistic           = "Average"
  threshold           = 1000000
  alarm_description   = "S3 object count is high for ${each.key}"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    BucketName  = each.value
    StorageType = "AllStorageTypes"
  }

  tags = var.common_tags
}

# WAF
resource "aws_cloudwatch_metric_alarm" "waf_blocked_requests" {
  for_each            = var.waf_web_acl_metrics
  alarm_name          = "${local.name_prefix}-${each.key}-waf-blocked-requests"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "BlockedRequests"
  namespace           = "AWS/WAFV2"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "WAF blocked request spike for ${each.key}"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    WebACL = each.value.web_acl
    Region = each.value.region
    Rule   = each.value.rule
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "waf_counted_requests" {
  for_each            = var.waf_web_acl_metrics
  alarm_name          = "${local.name_prefix}-${each.key}-waf-counted-requests"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CountedRequests"
  namespace           = "AWS/WAFV2"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "WAF counted request spike for ${each.key}"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    WebACL = each.value.web_acl
    Region = each.value.region
    Rule   = each.value.rule
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "waf_captcha_requests" {
  for_each            = var.waf_web_acl_metrics
  alarm_name          = "${local.name_prefix}-${each.key}-waf-captcha-requests"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "CaptchaRequests"
  namespace           = "AWS/WAFV2"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "WAF CAPTCHA requests detected for ${each.key}"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    WebACL = each.value.web_acl
    Region = each.value.region
    Rule   = each.value.rule
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "waf_challenge_requests" {
  for_each            = var.waf_web_acl_metrics
  alarm_name          = "${local.name_prefix}-${each.key}-waf-challenge-requests"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ChallengeRequests"
  namespace           = "AWS/WAFV2"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "WAF challenge requests detected for ${each.key}"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    WebACL = each.value.web_acl
    Region = each.value.region
    Rule   = each.value.rule
  }

  tags = var.common_tags
}

# Kinesis Video Streams
resource "aws_cloudwatch_metric_alarm" "kvs_put_media_errors" {
  for_each            = var.kvs_stream_names
  alarm_name          = "${local.name_prefix}-${each.key}-kvs-put-media-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "PutMedia.Errors"
  namespace           = "AWS/KinesisVideo"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "KVS PutMedia errors detected for ${each.key}"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    StreamName = each.value
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "kvs_get_media_errors" {
  for_each            = var.kvs_stream_names
  alarm_name          = "${local.name_prefix}-${each.key}-kvs-get-media-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "GetMedia.Errors"
  namespace           = "AWS/KinesisVideo"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "KVS GetMedia errors detected for ${each.key}"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    StreamName = each.value
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "kvs_incoming_bytes_low" {
  for_each            = var.kvs_stream_names
  alarm_name          = "${local.name_prefix}-${each.key}-kvs-incoming-bytes-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "PutMedia.IncomingBytes"
  namespace           = "AWS/KinesisVideo"
  period              = 300
  statistic           = "Sum"
  threshold           = 1000
  alarm_description   = "KVS incoming bytes are low for ${each.key}"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    StreamName = each.value
  }

  tags = var.common_tags
}

# EventBridge
resource "aws_cloudwatch_metric_alarm" "eventbridge_failed_invocations" {
  for_each            = var.eventbridge_rule_names
  alarm_name          = "${local.name_prefix}-${each.key}-eventbridge-failed-invocations"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FailedInvocations"
  namespace           = "AWS/Events"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "EventBridge failed invocations detected for ${each.key}"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    RuleName = each.value
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "eventbridge_throttled_rules" {
  for_each            = var.eventbridge_rule_names
  alarm_name          = "${local.name_prefix}-${each.key}-eventbridge-throttled-rules"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ThrottledRules"
  namespace           = "AWS/Events"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "EventBridge throttled rules detected for ${each.key}"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    RuleName = each.value
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "eventbridge_dead_letter_invocations" {
  for_each            = var.eventbridge_rule_names
  alarm_name          = "${local.name_prefix}-${each.key}-eventbridge-dlq-invocations"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "DeadLetterInvocations"
  namespace           = "AWS/Events"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "EventBridge dead-letter invocations detected for ${each.key}"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    RuleName = each.value
  }

  tags = var.common_tags
}

# Athena
resource "aws_cloudwatch_metric_alarm" "athena_query_failures" {
  for_each            = var.athena_workgroup_names
  alarm_name          = "${local.name_prefix}-${each.key}-athena-query-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "QueryFailed"
  namespace           = "AWS/Athena"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Athena query failures detected for ${each.key}"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    WorkGroup = each.value
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_metric_alarm" "athena_processed_bytes_high" {
  for_each            = var.athena_workgroup_names
  alarm_name          = "${local.name_prefix}-${each.key}-athena-processed-bytes-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ProcessedBytes"
  namespace           = "AWS/Athena"
  period              = 300
  statistic           = "Sum"
  threshold           = 1073741824
  alarm_description   = "Athena bytes scanned are high for ${each.key}"
  alarm_actions       = local.alarm_actions
  treat_missing_data  = "notBreaching"

  dimensions = {
    WorkGroup = each.value
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
            [".", "Duration", { stat = "Average" }],
            [".", "Throttles", { stat = "Sum" }]
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
