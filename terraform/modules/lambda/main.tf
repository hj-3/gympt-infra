locals {
  name_prefix = "${var.project_name}-${var.env}"
  
  lambda_functions = {
    agent-action              = { memory = 512, timeout = 30 }
    report-generator          = { memory = 1024, timeout = 300 }
    posture-event-processor   = { memory = 512, timeout = 60 }
    thumbnail-generator       = { memory = 1024, timeout = 60 }
    wearable-sync             = { memory = 512, timeout = 60 }
    recommendation-update     = { memory = 512, timeout = 60 }
    notification              = { memory = 256, timeout = 30 }
    export                    = { memory = 1024, timeout = 300 }
  }
}

# Lambda Execution Role
resource "aws_iam_role" "lambda" {
  name = "${local.name_prefix}-lambda-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = var.common_tags
}

# Basic Lambda execution policy
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda.name
}

# VPC execution policy (if Lambda in VPC)
resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  count      = var.vpc_config_enabled ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
  role       = aws_iam_role.lambda.name
}

# Custom policy for Lambda
resource "aws_iam_role_policy" "lambda_custom" {
  name = "${local.name_prefix}-lambda-custom-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = var.dynamodb_table_arns
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          for bucket_arn in var.s3_bucket_arns : "${bucket_arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = var.s3_bucket_arns
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = var.sqs_queue_arns
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = length(var.secrets_manager_arns) > 0 ? var.secrets_manager_arns : ["arn:aws:secretsmanager:${var.aws_region}:*:secret:${local.name_prefix}/*"]
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel"
        ]
        Resource = "arn:aws:bedrock:${var.aws_region}::foundation-model/*"
      },
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

# Lambda Functions
resource "aws_lambda_function" "functions" {
  for_each = local.lambda_functions

  function_name = "${local.name_prefix}-${each.key}"
  role          = aws_iam_role.lambda.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = each.value.timeout
  memory_size   = each.value.memory

  s3_bucket = var.lambda_artifact_bucket
  s3_key    = "${each.key}.zip"

  environment {
    variables = merge(
      {
        ENV              = var.env
        REGION           = var.aws_region
        LOG_LEVEL        = var.log_level
      },
      var.environment_variables
    )
  }

  dynamic "vpc_config" {
    for_each = var.vpc_config_enabled ? [1] : []
    content {
      subnet_ids         = var.vpc_subnet_ids
      security_group_ids = var.vpc_security_group_ids
    }
  }

  dynamic "dead_letter_config" {
    for_each = var.dlq_arn != null ? [1] : []
    content {
      target_arn = var.dlq_arn
    }
  }

  tracing_config {
    mode = var.xray_tracing_enabled ? "Active" : "PassThrough"
  }

  reserved_concurrent_executions = var.reserved_concurrent_executions

  tags = merge(
    var.common_tags,
    {
      Name     = "${local.name_prefix}-${each.key}"
      Function = each.key
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy.lambda_custom
  ]
}

# SQS Event Source Mappings
resource "aws_lambda_event_source_mapping" "sqs" {
  for_each = var.sqs_event_sources

  event_source_arn = each.value.queue_arn
  function_name    = aws_lambda_function.functions[each.key].arn
  batch_size       = each.value.batch_size
  enabled          = true

  scaling_config {
    maximum_concurrency = each.value.max_concurrency
  }
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "lambda" {
  for_each = local.lambda_functions

  name              = "/aws/lambda/${local.name_prefix}-${each.key}"
  retention_in_days = var.log_retention_days

  tags = merge(
    var.common_tags,
    {
      Name     = "${local.name_prefix}-${each.key}-logs"
      Function = each.key
    }
  )
}

# CloudWatch Alarms for Errors
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = local.lambda_functions

  alarm_name          = "${local.name_prefix}-${each.key}-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = var.error_alarm_threshold
  alarm_description   = "Lambda function ${each.key} error rate"
  alarm_actions       = var.alarm_actions

  dimensions = {
    FunctionName = aws_lambda_function.functions[each.key].function_name
  }

  tags = var.common_tags
}

# CloudWatch Alarms for Duration
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  for_each = local.lambda_functions

  alarm_name          = "${local.name_prefix}-${each.key}-duration"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Average"
  threshold           = each.value.timeout * 1000 * 0.8 # 80% of timeout
  alarm_description   = "Lambda function ${each.key} duration high"
  alarm_actions       = var.alarm_actions

  dimensions = {
    FunctionName = aws_lambda_function.functions[each.key].function_name
  }

  tags = var.common_tags
}
