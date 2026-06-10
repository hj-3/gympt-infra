locals {
  name_prefix = "${var.project_name}-${var.env}"
}

resource "aws_iam_role" "eks_pod_role" {
  for_each = var.pod_service_accounts
  name     = "${local.name_prefix}-${each.key}-pod-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(var.oidc_provider_url, "https://", "")}:aud" = "sts.amazonaws.com"
          "${replace(var.oidc_provider_url, "https://", "")}:sub" = "system:serviceaccount:${each.value.namespace}:${each.value.service_account}"
        }
      }
    }]
  })

  tags = merge(var.common_tags, { Name = "${local.name_prefix}-${each.key}-pod-role" })
}

resource "aws_iam_role_policy_attachment" "eks_pod_s3" {
  for_each   = { for k, v in var.pod_service_accounts : k => v if k != "posture-analysis-service" }
  role       = aws_iam_role.eks_pod_role[each.key].name
  policy_arn = aws_iam_policy.pod_s3_access.arn
}

resource "aws_iam_policy" "pod_s3_access" {
  name = "${local.name_prefix}-pod-s3-access"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket"
      ]
      Resource = var.s3_bucket_arns
    }]
  })
  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "eks_pod_dynamodb" {
  for_each   = { for k, v in var.pod_service_accounts : k => v if k != "agent-service" && k != "posture-analysis-service" }
  role       = aws_iam_role.eks_pod_role[each.key].name
  policy_arn = aws_iam_policy.pod_dynamodb_access.arn
}

resource "aws_iam_policy" "agent_service_dynamodb" {
  name = "${local.name_prefix}-agent-service-dynamodb"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:Query",
        "dynamodb:Scan"
      ]
      Resource = "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${local.name_prefix}-agent_interactions"
    }]
  })
  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "agent_service_dynamodb" {
  role       = aws_iam_role.eks_pod_role["agent-service"].name
  policy_arn = aws_iam_policy.agent_service_dynamodb.arn
}

# posture-analysis-service 전용 정책
resource "aws_iam_policy" "posture_analysis_s3" {
  name = "${local.name_prefix}-posture-analysis-s3"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject"]
        Resource = "arn:aws:s3:::${local.name_prefix}-media-${data.aws_caller_identity.current.account_id}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = "arn:aws:s3:::${local.name_prefix}-media-${data.aws_caller_identity.current.account_id}"
      }
    ]
  })
  tags = var.common_tags
}

resource "aws_iam_policy" "posture_analysis_dynamodb" {
  name = "${local.name_prefix}-posture-analysis-dynamodb"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:Query",
        "dynamodb:Scan",
        "dynamodb:BatchWriteItem"
      ]
      Resource = "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/${local.name_prefix}-posture_events"
    }]
  })
  tags = var.common_tags
}

resource "aws_iam_policy" "posture_analysis_kvs_signaling" {
  name = "${local.name_prefix}-posture-analysis-kvs-signaling"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "kinesisvideo:ConnectAsMaster",
        "kinesisvideo:GetSignalingChannelEndpoint",
        "kinesisvideo:DescribeSignalingChannel",
        "kinesisvideo:GetIceServerConfig"
      ]
      Resource = var.kvs_signaling_channel_arn
    }]
  })
  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "posture_analysis_s3" {
  role       = aws_iam_role.eks_pod_role["posture-analysis-service"].name
  policy_arn = aws_iam_policy.posture_analysis_s3.arn
}

resource "aws_iam_role_policy_attachment" "posture_analysis_dynamodb" {
  role       = aws_iam_role.eks_pod_role["posture-analysis-service"].name
  policy_arn = aws_iam_policy.posture_analysis_dynamodb.arn
}

resource "aws_iam_role_policy_attachment" "posture_analysis_kvs_signaling" {
  role       = aws_iam_role.eks_pod_role["posture-analysis-service"].name
  policy_arn = aws_iam_policy.posture_analysis_kvs_signaling.arn
}

resource "aws_iam_policy" "pod_dynamodb_access" {
  name = "${local.name_prefix}-pod-dynamodb-access"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:Query",
        "dynamodb:Scan"
      ]
      Resource = var.dynamodb_table_arns
    }]
  })
  tags = var.common_tags
}

# Bedrock access policy for agent-service
resource "aws_iam_policy" "pod_bedrock_access" {
  name = "${local.name_prefix}-pod-bedrock-access"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = [
          "arn:aws:bedrock:*::foundation-model/anthropic.claude-*",
          "arn:aws:bedrock:*:${data.aws_caller_identity.current.account_id}:inference-profile/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["bedrock:InvokeAgent"]
        Resource = "arn:aws:bedrock:${var.bedrock_region}:${data.aws_caller_identity.current.account_id}:agent/${var.bedrock_agent_id}"
      },
      {
        Effect   = "Allow"
        Action   = ["bedrock:Retrieve"]
        Resource = "arn:aws:bedrock:${var.bedrock_region}:${data.aws_caller_identity.current.account_id}:knowledge-base/*"
      }
    ]
  })
  tags = var.common_tags
}

# Attach Bedrock policy to agent-service role
resource "aws_iam_role_policy_attachment" "agent_service_bedrock" {
  role       = aws_iam_role.eks_pod_role["agent-service"].name
  policy_arn = aws_iam_policy.pod_bedrock_access.arn
}

# Bedrock Agent Service Role
resource "aws_iam_role" "bedrock_agent_role" {
  name = "${local.name_prefix}-bedrock-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "bedrock.amazonaws.com"
      }
      Action = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
        ArnLike = {
          "aws:SourceArn" = "arn:aws:bedrock:${var.bedrock_region}:${data.aws_caller_identity.current.account_id}:agent/*"
        }
      }
    }]
  })

  tags = merge(var.common_tags, { Name = "${local.name_prefix}-bedrock-role" })
}

# Bedrock Agent Inference Policy (Cross-Region)
resource "aws_iam_policy" "bedrock_agent_inference" {
  name = "${local.name_prefix}-bedrock-agent-inference"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BedrockAgentInferenceProfilesCrossRegion"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
          "bedrock:GetInferenceProfile",
          "bedrock:GetFoundationModel"
        ]
        Resource = [
          "arn:aws:bedrock:${var.bedrock_region}:${data.aws_caller_identity.current.account_id}:inference-profile/*",
          "arn:aws:bedrock:*::foundation-model/anthropic.claude-*"
        ]
      }
    ]
  })
  tags = var.common_tags
}

# Bedrock Agent S3 Access Policy
resource "aws_iam_policy" "bedrock_agent_s3" {
  name = "${local.name_prefix}-bedrock-agent-s3"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BedrockAgentS3Access"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          for arn in var.s3_bucket_arns : "${arn}/*"
        ]
      },
      {
        Sid    = "BedrockAgentS3ListBucket"
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = var.s3_bucket_arns
      }
    ]
  })
  tags = var.common_tags
}

# Bedrock Agent CloudWatch Logs Policy
resource "aws_iam_policy" "bedrock_agent_logs" {
  name = "${local.name_prefix}-bedrock-agent-logs"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BedrockAgentCloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:aws:logs:${var.bedrock_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock/*",
          "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/bedrock/*"
        ]
      }
    ]
  })
  tags = var.common_tags
}

# Attach policies to Bedrock Agent role
resource "aws_iam_role_policy_attachment" "bedrock_agent_inference" {
  role       = aws_iam_role.bedrock_agent_role.name
  policy_arn = aws_iam_policy.bedrock_agent_inference.arn
}

resource "aws_iam_role_policy_attachment" "bedrock_agent_s3" {
  role       = aws_iam_role.bedrock_agent_role.name
  policy_arn = aws_iam_policy.bedrock_agent_s3.arn
}

resource "aws_iam_role_policy_attachment" "bedrock_agent_logs" {
  role       = aws_iam_role.bedrock_agent_role.name
  policy_arn = aws_iam_policy.bedrock_agent_logs.arn
}

# Data source for current AWS account
data "aws_caller_identity" "current" {}

# External Secrets IRSA
resource "aws_iam_role" "external_secrets" {
  name = "${local.name_prefix}-external-secrets"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(var.oidc_provider_url, "https://", "")}:aud" = "sts.amazonaws.com"
          "${replace(var.oidc_provider_url, "https://", "")}:sub" = "system:serviceaccount:external-secrets:external-secrets"
        }
      }
    }]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy" "external_secrets" {
  name = "${local.name_prefix}-external-secrets-policy"
  role = aws_iam_role.external_secrets.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecrets"
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:*:secret:${var.project_name}/${var.env}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/${var.project_name}/${var.env}/*"
      }
    ]
  })
}
