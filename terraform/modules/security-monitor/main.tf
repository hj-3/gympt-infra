locals {
  name_prefix = "${var.project_name}-${var.env}"
}

# ── Lambda 코드 패키징 ────────────────────────────────────────────────────────
# zip은 /tmp에 생성해 git에 포함되지 않도록 함
data "archive_file" "security_monitor" {
  type        = "zip"
  source_file = "${path.module}/lambda/handler.py"
  output_path = "/tmp/gympt-prod-security-monitor.zip"
}

# ── CloudWatch Log Group ──────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "security_monitor" {
  name              = "/aws/lambda/${local.name_prefix}-security-monitor"
  retention_in_days = var.log_retention_days
  tags              = var.common_tags
}

# ── Athena 전용 워크그룹 ──────────────────────────────────────────────────────
# 기존 Grafana 워크그룹(gympt-prod-workgroup)과 분리해 결과를 security-monitor/ 폴더에 저장
resource "aws_athena_workgroup" "security_monitor" {
  name = "${local.name_prefix}-security-monitor-workgroup"

  configuration {
    result_configuration {
      output_location = "s3://${var.athena_results_bucket_id}/security-monitor/"
      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }

  tags = var.common_tags
}

# ── IAM Role ──────────────────────────────────────────────────────────────────
resource "aws_iam_role" "security_monitor" {
  name = "${local.name_prefix}-security-monitor-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy" "security_monitor" {
  name = "${local.name_prefix}-security-monitor-policy"
  role = aws_iam_role.security_monitor.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # CloudWatch Logs - Lambda 실행 로그
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.security_monitor.arn}:*"
      },
      # CloudTrail - 최근 이벤트 직접 조회 (정기 스캔용)
      {
        Effect   = "Allow"
        Action   = ["cloudtrail:LookupEvents"]
        Resource = "*"
      },
      # Athena - 전용 워크그룹에서만 쿼리 실행 허용
      {
        Effect = "Allow"
        Action = [
          "athena:StartQueryExecution",
          "athena:StopQueryExecution",
          "athena:GetQueryExecution",
          "athena:GetQueryResults"
        ]
        Resource = "arn:aws:athena:${var.aws_region}:${var.account_id}:workgroup/${aws_athena_workgroup.security_monitor.name}"
      },
      # Glue - Athena가 테이블 스키마를 읽기 위해 필요
      {
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetTable",
          "glue:GetTables",
          "glue:GetPartition",
          "glue:GetPartitions",
          "glue:BatchGetPartition"
        ]
        Resource = [
          "arn:aws:glue:${var.aws_region}:${var.account_id}:catalog",
          "arn:aws:glue:${var.aws_region}:${var.account_id}:database/${var.glue_database_name}",
          "arn:aws:glue:${var.aws_region}:${var.account_id}:table/${var.glue_database_name}/*"
        ]
      },
      # S3 로그 버킷 - Athena가 로그 파일 읽기 위해 필요 (읽기 전용)
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          var.logs_bucket_arn,
          "${var.logs_bucket_arn}/*"
        ]
      },
      # S3 Athena 결과 버킷 - security-monitor/ 폴더에만 읽쓰기
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:AbortMultipartUpload"
        ]
        Resource = [
          var.athena_results_bucket_arn,
          "${var.athena_results_bucket_arn}/security-monitor/*"
        ]
      },
      # Bedrock - Claude Haiku 호출 (cross-region inference profile)
      # us.* 모델은 foundation-model ARN + inference-profile ARN 둘 다 필요
      {
        Effect = "Allow"
        Action = ["bedrock:InvokeModel"]
        Resource = [
          "arn:aws:bedrock:*::foundation-model/anthropic.claude-haiku-4-5-20251001-v1:0",
          "arn:aws:bedrock:${var.bedrock_region}:${var.account_id}:inference-profile/${var.bedrock_model_id}"
        ]
      },
      # Secrets Manager - Slack 웹훅 URL 조회
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = var.slack_webhook_secret_arn
      }
    ]
  })
}

# ── Lambda 함수 ───────────────────────────────────────────────────────────────
# VPC 밖에 배치 - Bedrock(us-west-2) 직접 호출에 NAT 불필요
resource "aws_lambda_function" "security_monitor" {
  function_name    = "${local.name_prefix}-security-monitor"
  role             = aws_iam_role.security_monitor.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = 300
  memory_size      = 512
  filename         = data.archive_file.security_monitor.output_path
  source_code_hash = data.archive_file.security_monitor.output_base64sha256

  environment {
    variables = {
      ACCOUNT_ID        = var.account_id
      GLUE_DATABASE     = var.glue_database_name
      ATHENA_WORKGROUP  = aws_athena_workgroup.security_monitor.name
      BEDROCK_REGION    = var.bedrock_region
      BEDROCK_MODEL_ID  = var.bedrock_model_id
      SLACK_SECRET_NAME = var.slack_webhook_secret_name

      # 운영 파라미터 — Lambda 콘솔에서 직접 수정하면 즉시 반영
      VPC_FLOW_REJECT_THRESHOLD = tostring(var.vpc_flow_reject_threshold)
      VPC_FLOW_WINDOW_MINUTES   = tostring(var.vpc_flow_window_minutes)
      WAF_BLOCK_THRESHOLD       = tostring(var.waf_block_threshold)
      S3_ERROR_THRESHOLD        = tostring(var.s3_error_threshold)
      ALB_ERROR_THRESHOLD       = tostring(var.alb_error_threshold)
      SCHEDULE_MIN_LEVEL        = var.schedule_min_level
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.security_monitor,
    aws_iam_role_policy.security_monitor,
  ]

  tags = var.common_tags
}

# ── EventBridge Rule 1: CloudTrail 보안 이벤트 실시간 감지 ─────────────────────
resource "aws_cloudwatch_event_rule" "critical_cloudtrail" {
  name        = "${local.name_prefix}-security-critical-events"
  description = "IAM·SG·Trail·S3 정책 변경 등 보안 관련 CloudTrail 이벤트 실시간 감지"

  event_pattern = jsonencode({
    source        = ["aws.cloudtrail"]
    "detail-type" = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = [
        "PutUserPolicy", "AttachUserPolicy", "DetachUserPolicy",
        "CreateUser", "DeleteUser", "CreateAccessKey",
        "UpdateAssumeRolePolicy", "PutRolePolicy", "AttachRolePolicy",
        "AuthorizeSecurityGroupIngress", "RevokeSecurityGroupIngress",
        "DeleteTrail", "StopLogging", "UpdateTrail",
        "PutBucketPolicy", "DeleteBucketPolicy", "PutBucketAcl",
        "PutBucketPublicAccessBlock",
        "CreateSecret", "DeleteSecret"
      ]
    }
  })

  tags = var.common_tags
}

resource "aws_cloudwatch_event_target" "critical_cloudtrail" {
  rule      = aws_cloudwatch_event_rule.critical_cloudtrail.name
  target_id = "SecurityMonitorLambda"
  arn       = aws_lambda_function.security_monitor.arn
}

resource "aws_lambda_permission" "critical_cloudtrail" {
  statement_id  = "AllowEventBridgeCriticalCloudTrail"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.security_monitor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.critical_cloudtrail.arn
}

# ── EventBridge Rule 2: MFA 없는 콘솔 로그인 실시간 감지 ─────────────────────
resource "aws_cloudwatch_event_rule" "console_login_no_mfa" {
  name        = "${local.name_prefix}-security-console-login"
  description = "MFA 미사용 콘솔 로그인 실시간 감지"

  event_pattern = jsonencode({
    source        = ["aws.signin"]
    "detail-type" = ["AWS Console Sign In via CloudTrail"]
    detail = {
      additionalEventData = {
        MFAUsed = ["No"]
      }
    }
  })

  tags = var.common_tags
}

resource "aws_cloudwatch_event_target" "console_login_no_mfa" {
  rule      = aws_cloudwatch_event_rule.console_login_no_mfa.name
  target_id = "SecurityMonitorLambda"
  arn       = aws_lambda_function.security_monitor.arn
}

resource "aws_lambda_permission" "console_login_no_mfa" {
  statement_id  = "AllowEventBridgeConsoleLogin"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.security_monitor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.console_login_no_mfa.arn
}

# ── EventBridge Rule 3: 30분 정기 스캔 ───────────────────────────────────────
resource "aws_cloudwatch_event_rule" "scheduled_scan" {
  name                = "${local.name_prefix}-security-scheduled-scan"
  description         = "30분마다 S3 보안 로그 전체 분석"
  schedule_expression = "rate(30 minutes)"

  tags = var.common_tags
}

resource "aws_cloudwatch_event_target" "scheduled_scan" {
  rule      = aws_cloudwatch_event_rule.scheduled_scan.name
  target_id = "SecurityMonitorLambda"
  arn       = aws_lambda_function.security_monitor.arn
}

resource "aws_lambda_permission" "scheduled_scan" {
  statement_id  = "AllowEventBridgeScheduledScan"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.security_monitor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.scheduled_scan.arn
}
