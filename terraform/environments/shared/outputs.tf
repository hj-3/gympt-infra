output "github_actions_oidc_provider_arn" {
  description = "Shared GitHub Actions OIDC provider ARN"
  value       = module.github_oidc.oidc_provider_arn
}
