output "workgroup_name" {
  value = aws_athena_workgroup.main.name
}

output "database_name" {
  value = aws_athena_database.logs.name
}
