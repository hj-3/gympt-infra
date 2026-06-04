locals {
  name_prefix = "${var.project_name}-${var.env}"
}

resource "aws_cloudtrail" "main" {
  name                          = "${local.name_prefix}-trail"
  s3_bucket_name                = var.s3_bucket_name
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  tags = merge(var.common_tags, { Name = "${local.name_prefix}-trail" })

  depends_on = [var.s3_bucket_policy_id]
}
