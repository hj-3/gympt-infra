data "aws_caller_identity" "current" {}

data "tls_certificate" "github_actions" {
  count = var.create_oidc_provider ? 1 : 0
  url   = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  count = var.create_oidc_provider ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github_actions[0].certificates[0].sha1_fingerprint]

  tags = merge(var.common_tags, {
    Name = "github-actions-oidc"
  })
}

data "aws_iam_openid_connect_provider" "github_actions" {
  count = var.create_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

locals {
  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github_actions[0].arn : data.aws_iam_openid_connect_provider.github_actions[0].arn

  github_subjects = [
    for branch in var.allowed_branches :
    "repo:${var.github_repository}:ref:refs/heads/${branch}"
  ]

  ecr_repository_resources = length(var.ecr_repository_arns) > 0 ? var.ecr_repository_arns : ["*"]

  frontend_bucket_resources = var.frontend_bucket_arn == null ? [] : [
    var.frontend_bucket_arn,
    "${var.frontend_bucket_arn}/*"
  ]

  lambda_artifact_bucket_resources = var.lambda_artifacts_bucket_arn == null ? [] : [
    var.lambda_artifacts_bucket_arn,
    "${var.lambda_artifacts_bucket_arn}/*"
  ]

  s3_resources = concat(local.frontend_bucket_resources, local.lambda_artifact_bucket_resources)

  cloudfront_distribution_resources = length(var.cloudfront_distribution_arns) > 0 ? var.cloudfront_distribution_arns : ["*"]

  lambda_function_resources = [
    "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.project_name}-${var.env}-*"
  ]
}

resource "aws_iam_role" "github_actions_app" {
  name = "github-actions-app-${var.env}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = local.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = local.github_subjects
        }
      }
    }]
  })

  tags = merge(var.common_tags, {
    Name = "github-actions-app-${var.env}-role"
  })
}

resource "aws_iam_policy" "github_actions_app" {
  name        = "github-actions-app-${var.env}-policy"
  description = "Permissions for gympt-app GitHub Actions ${var.env} deployments"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid    = "EcrAuthorization"
          Effect = "Allow"
          Action = [
            "ecr:GetAuthorizationToken"
          ]
          Resource = "*"
        },
        {
          Sid    = "EcrPush"
          Effect = "Allow"
          Action = [
            "ecr:BatchCheckLayerAvailability",
            "ecr:CompleteLayerUpload",
            "ecr:DescribeImages",
            "ecr:DescribeRepositories",
            "ecr:InitiateLayerUpload",
            "ecr:ListImages",
            "ecr:PutImage",
            "ecr:UploadLayerPart"
          ]
          Resource = local.ecr_repository_resources
        },
        {
          Sid    = "StsReadIdentity"
          Effect = "Allow"
          Action = [
            "sts:GetCallerIdentity"
          ]
          Resource = "*"
        }
      ],
      length(local.s3_resources) == 0 ? [] : [
        {
          Sid    = "S3DeployArtifacts"
          Effect = "Allow"
          Action = [
            "s3:DeleteObject",
            "s3:GetObject",
            "s3:ListBucket",
            "s3:PutObject"
          ]
          Resource = local.s3_resources
        }
      ],
      [
        {
          Sid    = "CloudFrontInvalidation"
          Effect = "Allow"
          Action = [
            "cloudfront:CreateInvalidation",
            "cloudfront:GetDistribution"
          ]
          Resource = local.cloudfront_distribution_resources
        },
        {
          Sid    = "LambdaUpdateCode"
          Effect = "Allow"
          Action = [
            "lambda:GetFunction",
            "lambda:UpdateFunctionCode"
          ]
          Resource = local.lambda_function_resources
        }
      ]
    )
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "github_actions_app" {
  role       = aws_iam_role.github_actions_app.name
  policy_arn = aws_iam_policy.github_actions_app.arn
}
