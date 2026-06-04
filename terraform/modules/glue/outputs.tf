output "catalog_database_name" {
  value = aws_glue_catalog_database.main.name
}

output "crawler_name" {
  value = aws_glue_crawler.logs.name
}

output "glue_role_arn" {
  value = aws_iam_role.glue.arn
}
