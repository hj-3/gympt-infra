output "catalog_database_name" {
  value = aws_glue_catalog_database.main.name
}

output "crawler_name" {
  value = aws_glue_crawler.logs.name
}

output "glue_role_arn" {
  value = aws_iam_role.glue.arn
}

output "catalog_table_names" {
  value = {
    alb_access_logs        = aws_glue_catalog_table.alb_access_logs.name
    cloudfront_access_logs = aws_glue_catalog_table.cloudfront_access_logs.name
    cloudtrail_logs        = aws_glue_catalog_table.cloudtrail_logs.name
    inspector_findings     = aws_glue_catalog_table.inspector_findings.name
    s3_access_logs         = aws_glue_catalog_table.s3_access_logs.name
    vpc_flow_logs          = aws_glue_catalog_table.vpc_flow_logs.name
    waf_alb_logs           = aws_glue_catalog_table.waf_alb_logs.name
    waf_cloudfront_logs    = aws_glue_catalog_table.waf_cloudfront_logs.name
  }
}
