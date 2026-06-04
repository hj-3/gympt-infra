#!/bin/bash
# terraform/environments/prod 에서 실행
# v3에서 실패한 것들만: SG(ID 직접 지정) + Lambda(이스케이프 수정)

set -e

# SG ID 조회
echo "=== SG ID 조회 중 ==="
VPC_ID=$(aws ec2 describe-vpcs --region ap-northeast-2 \
  --filters "Name=tag:Name,Values=gympt-prod-vpc" \
  --query 'Vpcs[0].VpcId' --output text)
echo "VPC ID: $VPC_ID"

RDS_SG_ID=$(aws ec2 describe-security-groups --region ap-northeast-2 \
  --filters "Name=group-name,Values=gympt-prod-rds-*" "Name=vpc-id,Values=$VPC_ID" \
  --query 'SecurityGroups[0].GroupId' --output text)
echo "RDS SG: $RDS_SG_ID"

REDIS_SG_ID=$(aws ec2 describe-security-groups --region ap-northeast-2 \
  --filters "Name=group-name,Values=gympt-prod-redis-*" "Name=vpc-id,Values=$VPC_ID" \
  --query 'SecurityGroups[0].GroupId' --output text)
echo "Redis SG: $REDIS_SG_ID"

echo ""
echo "=== RDS Security Group ==="
[ "$RDS_SG_ID" != "None" ] && terraform import 'module.rds.aws_security_group.rds' "$RDS_SG_ID" || echo "RDS SG 없음 - apply에서 생성됨"

echo "=== ElastiCache Security Group ==="
[ "$REDIS_SG_ID" != "None" ] && terraform import 'module.elasticache.aws_security_group.redis' "$REDIS_SG_ID" || echo "Redis SG 없음 - apply에서 생성됨"

echo ""
echo "=== Lambda Functions ==="
# 이스케이프 버그 수정: 각각 개별 명령으로
terraform import 'module.lambda.aws_lambda_function.functions["agent-action"]'            gympt-prod-agent-action            || echo "없음 - apply에서 생성"
terraform import 'module.lambda.aws_lambda_function.functions["report-generator"]'        gympt-prod-report-generator        || echo "없음 - apply에서 생성"
terraform import 'module.lambda.aws_lambda_function.functions["posture-event-processor"]' gympt-prod-posture-event-processor || echo "없음 - apply에서 생성"
terraform import 'module.lambda.aws_lambda_function.functions["thumbnail-generator"]'     gympt-prod-thumbnail-generator     || echo "없음 - apply에서 생성"
terraform import 'module.lambda.aws_lambda_function.functions["wearable-sync"]'           gympt-prod-wearable-sync           || echo "없음 - apply에서 생성"
terraform import 'module.lambda.aws_lambda_function.functions["recommendation-update"]'   gympt-prod-recommendation-update   || echo "없음 - apply에서 생성"
terraform import 'module.lambda.aws_lambda_function.functions["notification"]'            gympt-prod-notification            || echo "없음 - apply에서 생성"
terraform import 'module.lambda.aws_lambda_function.functions["export"]'                  gympt-prod-export                  || echo "없음 - apply에서 생성"

echo ""
echo "=== 완료. terraform plan 실행하세요 ==="
