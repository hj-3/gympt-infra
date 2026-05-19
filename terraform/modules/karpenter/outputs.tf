output "controller_role_arn" {
  value = aws_iam_role.karpenter_controller.arn
}

output "node_instance_profile_name" {
  value = aws_iam_instance_profile.karpenter_node.name
}
