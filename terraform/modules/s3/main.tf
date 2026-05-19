locals {
  name_prefix = "${var.project_name}-${var.env}"
}

# Frontend Bucket
resource "aws_s3_bucket" "frontend" {
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
  bucket = aws_s3_bucket.frontend.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

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
    id     = "delete-old-logs"
    status = "Enabled"

    expiration {
      days = 90
    }
  }
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
