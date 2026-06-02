#!/bin/bash
# terraform/environments/prod 에서 실행
# state list 확인 후 빠진 것들만 추림
# import 실패해도 계속 진행 (|| true)

echo "=== EKS Cluster ==="
terraform import 'module.eks.aws_eks_cluster.main' gympt-prod-eks || true
terraform import 'module.eks.aws_iam_openid_connect_provider.cluster'   "$(aws eks describe-cluster --name gympt-prod-eks --region ap-northeast-2      --query 'cluster.identity.oidc.issuer' --output text)" || true
terraform import 'module.eks.aws_iam_role.ebs_csi' gympt-prod-ebs-csi-driver || true
terraform import 'module.eks.aws_iam_role_policy_attachment.cluster_policy'   "gympt-prod-eks-cluster-role/arn:aws:iam::aws:policy/AmazonEKSClusterPolicy" || true
terraform import 'module.eks.aws_iam_role_policy_attachment.vpc_resource_controller'   "gympt-prod-eks-cluster-role/arn:aws:iam::aws:policy/AmazonEKSVPCResourceController" || true

echo "=== EKS Node Groups ==="
terraform import 'module.eks.aws_eks_node_group.general' "gympt-prod-eks:gympt-prod-general" || true
terraform import 'module.eks.aws_eks_node_group.gpu[0]' "gympt-prod-eks:gympt-prod-gpu" || true

echo "=== EKS Addons ==="
terraform import 'module.eks.aws_eks_addon.vpc_cni'       "gympt-prod-eks:vpc-cni" || true
terraform import 'module.eks.aws_eks_addon.coredns'       "gympt-prod-eks:coredns" || true
terraform import 'module.eks.aws_eks_addon.kube_proxy'    "gympt-prod-eks:kube-proxy" || true
terraform import 'module.eks.aws_eks_addon.ebs_csi_driver' "gympt-prod-eks:aws-ebs-csi-driver" || true
terraform import 'module.eks.aws_iam_role_policy_attachment.ebs_csi'   "gympt-prod-ebs-csi-driver/arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy" || true

echo "=== IAM ==="
terraform import 'module.iam.aws_iam_role.bedrock_agent_role' gympt-prod-bedrock-role || true
terraform import 'module.iam.aws_iam_role.eks_pod_role'       gympt-prod-eks-pod-role || true
terraform import 'module.iam.aws_iam_policy.pod_s3_access'   "arn:aws:iam::337112169365:policy/gympt-prod-pod-s3-access" || true
terraform import 'module.iam.aws_iam_policy.bedrock_agent_s3'   "arn:aws:iam::337112169365:policy/gympt-prod-bedrock-agent-s3" || true
terraform import 'module.github_oidc.aws_iam_policy.github_actions_app'   "arn:aws:iam::337112169365:policy/github-actions-app-prod-policy" || true

echo "=== RDS ==="
terraform import 'module.rds.aws_db_subnet_group.main'    gympt-prod-db-subnet-group || true
terraform import 'module.rds.aws_db_parameter_group.main' gympt-prod-postgres-params || true
terraform import 'module.rds.aws_db_instance.main'        gympt-prod-postgres || true
terraform import 'module.rds.aws_security_group.rds'   "$(aws ec2 describe-security-groups --region ap-northeast-2      --filters Name=group-name,Values="gympt-prod-rds-*" Name=vpc-id,Values=$(aws ec2 describe-vpcs      --region ap-northeast-2 --filters Name=tag:Name,Values="gympt-prod-vpc"      --query 'Vpcs[0].VpcId' --output text)      --query 'SecurityGroups[0].GroupId' --output text)" || true

echo "=== ElastiCache ==="
terraform import 'module.elasticache.aws_elasticache_replication_group.main' gympt-prod-redis || true
terraform import 'module.elasticache.aws_security_group.redis'   "$(aws ec2 describe-security-groups --region ap-northeast-2      --filters Name=group-name,Values="gympt-prod-redis-*"      --query 'SecurityGroups[0].GroupId' --output text)" || true

echo "=== S3 ==="
terraform import 'module.s3.aws_s3_bucket.logs'             gympt-prod-logs-337112169365 || true
terraform import 'module.s3.aws_s3_bucket.lambda_artifacts' gympt-prod-lambda-artifacts-337112169365 || true
terraform import 'module.s3.aws_s3_bucket.athena_results'   gympt-prod-athena-results-337112169365 || true

echo "=== Karpenter ==="
terraform import 'module.karpenter.aws_iam_role.karpenter_controller'   gympt-prod-karpenter-controller || true

echo "=== Lambda Functions ==="
for fn in agent-action report-generator posture-event-processor thumbnail-generator            wearable-sync recommendation-update notification export; do
  terraform import "module.lambda.aws_lambda_function.functions[\"\"]"     "gympt-prod-" || true
done
terraform import 'module.lambda.aws_iam_role_policy.lambda_custom'   "gympt-prod-lambda-execution-role:gympt-prod-lambda-custom-policy" || true

echo ""
echo "=== 완료. 이제 terraform plan 실행하세요 ==="
