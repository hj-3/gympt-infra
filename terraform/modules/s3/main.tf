locals {
  name_prefix = "${var.project_name}-${var.env}"
}

# Frontend Bucket (조건부 생성)
resource "aws_s3_bucket" "frontend" {
  count  = var.create_frontend ? 1 : 0
  bucket = "${local.name_prefix}-frontend-${var.account_id}"

  tags = merge(
    var.common_tags,
    {
      Name = "${local.name_prefix}-frontend"
      Type = "frontend"
    }
  )
}

resource "aws_s3_bucket_versioning" "frontend" {
  count  = var.create_frontend ? 1 : 0
  bucket = aws_s3_bucket.frontend[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  count  = var.create_frontend ? 1 : 0
  bucket = aws_s3_bucket.frontend[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  count  = var.create_frontend ? 1 : 0
  bucket = aws_s3_bucket.frontend[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
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

# CloudTrail bucket policy
resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.logs.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.logs.arn}/cloudtrail/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Sid    = "AWSVPCFlowLogsWrite"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.logs.arn}/vpc-flow-logs/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Sid    = "AWSVPCFlowLogsAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.logs.arn
      }
    ]
  })
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
