output "lambda_function_arn" {
  value = aws_lambda_function.security_monitor.arn
}

output "lambda_function_name" {
  value = aws_lambda_function.security_monitor.function_name
}

output "lambda_role_arn" {
  value = aws_iam_role.security_monitor.arn
}

output "athena_workgroup_name" {
  value = aws_athena_workgroup.security_monitor.name
}
