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
  for_each   = var.pod_service_accounts
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
  for_each   = var.pod_service_accounts
  role       = aws_iam_role.eks_pod_role[each.key].name
  policy_arn = aws_iam_policy.pod_dynamodb_access.arn
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
          "arn:aws:bedrock:us-west-2::foundation-model/anthropic.claude-*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock-agent-runtime:InvokeAgent",
          "bedrock-agent-runtime:Retrieve"
        ]
        Resource = "*"
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
