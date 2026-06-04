locals {
  name_prefix = "${var.project_name}-${var.env}"
}

resource "aws_glue_catalog_database" "main" {
  name = "${replace(local.name_prefix, "-", "_")}_catalog"
}

resource "aws_glue_crawler" "logs" {
  name          = "${local.name_prefix}-logs-crawler"
  role          = aws_iam_role.glue.arn
  database_name = aws_glue_catalog_database.main.name

  s3_target {
    path = "s3://${var.logs_bucket}/logs/"
  }

  tags = var.common_tags
}

resource "aws_iam_role" "glue" {
  name = "${local.name_prefix}-glue-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "glue.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "glue" {
  role       = aws_iam_role.glue.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "glue_s3" {
  name = "${local.name_prefix}-glue-s3"
  role = aws_iam_role.glue.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject"
      ]
      Resource = [
        "arn:aws:s3:::${var.logs_bucket}/*"
      ]
    }]
  })
}
