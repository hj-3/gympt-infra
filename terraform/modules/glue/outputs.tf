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
    alb_access_logs = aws_glue_catalog_table.alb_access_logs.name
    cloudtrail_logs = aws_glue_catalog_table.cloudtrail_logs.name
    vpc_flow_logs   = aws_glue_catalog_table.vpc_flow_logs.name
  }
}
