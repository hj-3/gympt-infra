output "pod_role_arns" {
  value = { for k, v in aws_iam_role.eks_pod_role : k => v.arn }
}

output "bedrock_agent_role_arn" {
  description = "ARN of the Bedrock Agent IAM role"
  value       = aws_iam_role.bedrock_agent_role.arn
}

output "bedrock_agent_role_name" {
  description = "Name of the Bedrock Agent IAM role"
  value       = aws_iam_role.bedrock_agent_role.name
}

output "external_secrets_role_arn" {
  value = aws_iam_role.external_secrets.arn
}
