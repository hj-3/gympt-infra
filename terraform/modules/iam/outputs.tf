output "pod_role_arns" {
  value = { for k, v in aws_iam_role.eks_pod_role : k => v.arn }
}
