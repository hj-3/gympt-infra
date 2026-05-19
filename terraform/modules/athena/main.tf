locals {
  name_prefix = "${var.project_name}-${var.env}"
}

resource "aws_athena_workgroup" "main" {
  name = "${local.name_prefix}-workgroup"
  configuration {
    result_configuration {
      output_location = "s3://${var.results_bucket}/athena-results/"
      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }
  tags = var.common_tags
}

resource "aws_athena_database" "logs" {
  name   = "${replace(local.name_prefix, "-", "_")}_logs"
  bucket = var.results_bucket
}
