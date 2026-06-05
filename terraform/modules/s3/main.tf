locals {
  name_prefix = "${var.project_name}-${var.env}"
}

# Media Bucket
resource "aws_s3_bucket" "media" {
  bucket = "${local.name_prefix}-media-${var.account_id}"

  tags = merge(
    var.common_tags,
    {
      Name = "${local.name_prefix}-media"
      Type = "media"
    }
  )
}

resource "aws_s3_bucket_lifecycle_configuration" "media" {
  bucket = aws_s3_bucket.media.id

  rule {
    id     = "transition-to-ia"
    status = "Enabled"

    filter {}

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }
  }
}

# Logs Bucket
resource "aws_s3_bucket" "logs" {
  bucket = "${local.name_prefix}-logs-${var.account_id}"

  tags = merge(
    var.common_tags,
    {
      Name = "${local.name_prefix}-logs"
      Type = "logs"
    }
  )
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "logs-lifecycle"
    status = "Enabled"

    filter {}

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}

# Logs bucket policy
resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # CloudTrail
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.logs.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.logs.arn}/cloudtrail/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      },
      # VPC Flow Logs
      {
        Sid    = "AWSVPCFlowLogsAclCheck"
        Effect = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.logs.arn
      },
      {
        Sid    = "AWSVPCFlowLogsWrite"
        Effect = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.logs.arn}/vpc-flow-logs/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      },
      # ALB Access Logs (ap-northeast-2 ELB service account: 600734575887)
      {
        Sid    = "ALBAccessLogsWrite"
        Effect = "Allow"
        Principal = { AWS = "arn:aws:iam::600734575887:root" }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.logs.arn}/alb-access-logs/*"
      },
      # S3 Server Access Logs
      {
        Sid    = "S3AccessLogsWrite"
        Effect = "Allow"
        Principal = { Service = "logging.s3.amazonaws.com" }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.logs.arn}/s3-access-logs/*"
        Condition = {
          StringEquals = { "aws:SourceAccount" = var.account_id }
        }
      },
      # Kinesis Firehose (WAF logs, EKS audit logs, Inspector findings)
      {
        Sid    = "FirehoseDeliveryWrite"
        Effect = "Allow"
        Principal = { Service = "firehose.amazonaws.com" }
        Action   = ["s3:PutObject", "s3:PutObjectAcl"]
        Resource = [
          "${aws_s3_bucket.logs.arn}/waf-logs/*",
          "${aws_s3_bucket.logs.arn}/eks-audit-logs/*",
          "${aws_s3_bucket.logs.arn}/inspector-findings/*",
        ]
        Condition = {
          StringEquals = { "aws:SourceAccount" = var.account_id }
        }
      },
      # CloudFront Access Logs (V2, CloudWatch Logs vended delivery)
      {
        Sid    = "CloudFrontLogsWrite"
        Effect = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.logs.arn}/cloudfront-logs/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"      = "bucket-owner-full-control"
            "aws:SourceAccount" = var.account_id
          }
        }
      }
    ]
  })
}

# S3 server access logging for other buckets
resource "aws_s3_bucket_logging" "media" {
  bucket        = aws_s3_bucket.media.id
  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "s3-access-logs/media/"
}

resource "aws_s3_bucket_logging" "lambda_artifacts" {
  bucket        = aws_s3_bucket.lambda_artifacts.id
  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "s3-access-logs/lambda-artifacts/"
}

resource "aws_s3_bucket_logging" "athena_results" {
  bucket        = aws_s3_bucket.athena_results.id
  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "s3-access-logs/athena-results/"
}

# Lambda Artifacts Bucket
resource "aws_s3_bucket" "lambda_artifacts" {
  bucket = "${local.name_prefix}-lambda-artifacts-${var.account_id}"

  tags = merge(
    var.common_tags,
    {
      Name = "${local.name_prefix}-lambda-artifacts"
      Type = "lambda-artifacts"
    }
  )
}

# Athena Results Bucket
resource "aws_s3_bucket" "athena_results" {
  bucket = "${local.name_prefix}-athena-results-${var.account_id}"

  tags = merge(
    var.common_tags,
    {
      Name = "${local.name_prefix}-athena-results"
      Type = "athena-results"
    }
  )
}
