output "oidc_provider_arn" {
  description = "GitHub Actions OIDC provider ARN"
  value       = local.oidc_provider_arn
}

output "github_actions_app_role_arn" {
  description = "IAM role ARN for gympt-app GitHub Actions"
  value       = try(aws_iam_role.github_actions_app[0].arn, null)
}

output "github_actions_app_role_name" {
  description = "IAM role name for gympt-app GitHub Actions"
  value       = try(aws_iam_role.github_actions_app[0].name, null)
}
