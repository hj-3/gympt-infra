# 배포 절차

## 목차
- [초기 설정](#초기-설정)
- [Dev 환경 배포](#dev-환경-배포)
- [Prod 환경 배포](#prod-환경-배포)
- [업데이트 및 변경](#업데이트-및-변경)
- [롤백](#롤백)

## 초기 설정

### 1. 사전 요구사항

**필수 도구**:
```bash
# Terraform 설치
brew install terraform

# AWS CLI 설치
brew install awscli

# kubectl 설치
brew install kubectl

# 버전 확인
terraform version  # >= 1.5.0
aws --version      # >= 2.0.0
kubectl version    # >= 1.28.0
```

**AWS 자격증명 구성**:
```bash
aws configure

# 입력 값:
AWS Access Key ID: [YOUR_ACCESS_KEY]
AWS Secret Access Key: [YOUR_SECRET_KEY]
Default region name: ap-northeast-2
Default output format: json

# 자격증명 확인
aws sts get-caller-identity
```

### 2. Repository 클론

```bash
# Repository 클론
git clone https://github.com/your-org/gympt-infra.git
cd gympt-infra

# 구조 확인
ls -la
```

### 3. S3 백엔드 초기화

**자동 초기화** (권장):
```bash
# 스크립트 실행
./scripts/init-backend.sh

# 출력 예시:
# Creating S3 backend bucket: gympt-tfstate-123456789012
# ✓ S3 bucket created
# ✓ Versioning enabled
# ✓ Encryption enabled
# ✓ Public access blocked
# ✓ DynamoDB table created
```

**수동 초기화**:
```bash
# 계정 ID 확인
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# S3 버킷 생성
aws s3api create-bucket \
  --bucket gympt-tfstate-${ACCOUNT_ID} \
  --region ap-northeast-2 \
  --create-bucket-configuration LocationConstraint=ap-northeast-2

# 버전 관리 활성화
aws s3api put-bucket-versioning \
  --bucket gympt-tfstate-${ACCOUNT_ID} \
  --versioning-configuration Status=Enabled

# 암호화 활성화
aws s3api put-bucket-encryption \
  --bucket gympt-tfstate-${ACCOUNT_ID} \
  --server-side-encryption-configuration \
    '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]}'

# Public Access Block
aws s3api put-public-access-block \
  --bucket gympt-tfstate-${ACCOUNT_ID} \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# DynamoDB 테이블 생성
aws dynamodb create-table \
  --table-name gympt-tfstate-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ap-northeast-2
```

### 4. Secrets 생성

```bash
# RDS 마스터 비밀번호 생성
aws secretsmanager create-secret \
  --name gympt/dev/rds-password \
  --secret-string "{\"username\":\"gympt_admin\",\"password\":\"$(openssl rand -base64 32)\"}" \
  --region ap-northeast-2

# Secret ARN 확인
aws secretsmanager describe-secret \
  --secret-id gympt/dev/rds-password \
  --query ARN \
  --output text
```

## Dev 환경 배포

### 1. 환경 변수 파일 생성

```bash
cd terraform/environments/dev

# terraform.tfvars 생성
cat > terraform.tfvars <<EOF
environment = "dev"
vpc_cidr    = "10.0.0.0/16"

# RDS 설정
rds_instance_class  = "db.t3.medium"
rds_multi_az        = false
rds_master_password_secret_arn = "arn:aws:secretsmanager:ap-northeast-2:ACCOUNT_ID:secret:gympt/dev/rds-password-XXXXX"

# ElastiCache 설정
redis_node_type  = "cache.t3.medium"
redis_num_nodes  = 1

# EKS 설정
eks_cluster_version = "1.28"

# Bedrock 활성화
enable_bedrock = true

# 태그
tags = {
  Environment = "dev"
  Project     = "gympt"
  ManagedBy   = "terraform"
  Owner       = "devops-team"
}
EOF
```

### 2. Terraform 초기화

```bash
# Backend 구성과 함께 초기화
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

terraform init \
  -backend-config="bucket=gympt-tfstate-${ACCOUNT_ID}" \
  -backend-config="key=dev/terraform.tfstate" \
  -backend-config="region=ap-northeast-2" \
  -backend-config="dynamodb_table=gympt-tfstate-lock"

# 출력 예시:
# Initializing the backend...
# Initializing provider plugins...
# Terraform has been successfully initialized!
```

### 3. Plan 실행

```bash
# Plan 생성
terraform plan -out=tfplan

# Plan 검토
# - 생성될 리소스 확인
# - 변경 사항 검토
# - 비용 예측
```

**예상 리소스**:
```
Plan: 150+ resources to add, 0 to change, 0 to destroy.

주요 리소스:
- VPC (1)
- Subnets (9)
- NAT Gateway (1-3)
- EKS Cluster (1)
- EKS Node Groups (2-3)
- RDS Instance (1)
- ElastiCache Cluster (1)
- S3 Buckets (3-5)
- SQS Queues (4-6)
- Lambda Functions (5-7)
```

### 4. Apply 실행

```bash
# Apply 실행
terraform apply tfplan

# 진행 상황 모니터링
# - 각 리소스 생성 시간 확인
# - 에러 발생 시 즉시 확인
```

**예상 소요 시간**:
- VPC 및 네트워크: 2-5분
- EKS 클러스터: 15-20분
- RDS 인스턴스: 10-15분
- ElastiCache: 5-10분
- 기타 리소스: 5-10분
- **총 소요 시간: 40-60분**

### 5. 출력값 확인

```bash
# 모든 출력값 확인
terraform output

# 특정 출력값 확인
terraform output eks_cluster_endpoint
terraform output rds_endpoint
terraform output redis_endpoint
```

### 6. kubeconfig 설정

**스크립트 사용** (권장):
```bash
cd ../../..
./scripts/get-kubeconfig.sh dev

# 클러스터 접근 확인
kubectl get nodes
kubectl get namespaces
```

**수동 설정**:
```bash
# kubeconfig 업데이트
aws eks update-kubeconfig \
  --region ap-northeast-2 \
  --name gympt-dev-cluster \
  --alias gympt-dev

# Context 전환
kubectl config use-context gympt-dev

# 노드 확인
kubectl get nodes
```

### 7. 배포 검증

**스크립트 사용**:
```bash
./scripts/utilities/check-resources.sh dev
```

**수동 검증**:
```bash
# EKS 노드 확인
kubectl get nodes
kubectl top nodes

# VPC 확인
aws ec2 describe-vpcs \
  --filters "Name=tag:Environment,Values=dev" \
  --query 'Vpcs[0].VpcId' \
  --output text

# RDS 확인
aws rds describe-db-instances \
  --db-instance-identifier gympt-dev-postgres \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text

# ElastiCache 확인
aws elasticache describe-cache-clusters \
  --cache-cluster-id gympt-dev-redis \
  --query 'CacheClusters[0].CacheClusterStatus' \
  --output text

# S3 버킷 확인
aws s3 ls | grep gympt-dev
```

## Prod 환경 배포

### 1. 환경 변수 파일 생성

```bash
cd terraform/environments/prod

cat > terraform.tfvars <<EOF
environment = "prod"
vpc_cidr    = "10.1.0.0/16"

# RDS 설정 (Multi-AZ)
rds_instance_class          = "db.r6i.xlarge"
rds_multi_az                = true
rds_backup_retention_period = 30
rds_master_password_secret_arn = "arn:aws:secretsmanager:ap-northeast-2:ACCOUNT_ID:secret:gympt/prod/rds-password-XXXXX"

# ElastiCache 설정 (Cluster)
redis_node_type  = "cache.r6g.large"
redis_num_nodes  = 3

# EKS 설정
eks_cluster_version = "1.28"

# NAT Gateway (각 AZ)
nat_gateway_per_az = true

# Bedrock 활성화
enable_bedrock = true

# 태그
tags = {
  Environment = "prod"
  Project     = "gympt"
  ManagedBy   = "terraform"
  Owner       = "devops-team"
  CostCenter  = "engineering"
}
EOF
```

### 2. Prod Secrets 생성

```bash
# Prod RDS 비밀번호
aws secretsmanager create-secret \
  --name gympt/prod/rds-password \
  --secret-string "{\"username\":\"gympt_admin\",\"password\":\"$(openssl rand -base64 32)\"}" \
  --region ap-northeast-2

# 비밀번호 자동 교체 설정 (30일)
aws secretsmanager rotate-secret \
  --secret-id gympt/prod/rds-password \
  --rotation-lambda-arn arn:aws:lambda:ap-northeast-2:ACCOUNT_ID:function:SecretsManagerRotation \
  --rotation-rules AutomaticallyAfterDays=30
```

### 3. Terraform 초기화 및 배포

```bash
# 초기화 (별도 State 파일)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

terraform init \
  -backend-config="bucket=gympt-tfstate-${ACCOUNT_ID}" \
  -backend-config="key=prod/terraform.tfstate" \
  -backend-config="region=ap-northeast-2" \
  -backend-config="dynamodb_table=gympt-tfstate-lock"

# Plan 생성
terraform plan -out=tfplan

# 검토 후 Apply
terraform apply tfplan
```

### 4. Prod 검증

```bash
# kubeconfig 설정
./scripts/get-kubeconfig.sh prod

# 리소스 확인
./scripts/utilities/check-resources.sh prod

# 모니터링 확인
# - CloudWatch Dashboard
# - 알람 설정
# - 로그 스트림
```

## 업데이트 및 변경

### 인프라 변경

```bash
cd terraform/environments/dev

# 변경 사항 적용
terraform plan -out=tfplan
terraform apply tfplan
```

### 모듈 버전 업그레이드

```bash
# 1. 모듈 변경 사항 확인
git diff modules/eks

# 2. Plan 실행
terraform plan

# 3. 영향 범위 확인
# - 어떤 리소스가 변경되는지
# - Downtime이 발생하는지

# 4. Apply
terraform apply
```

### EKS 버전 업그레이드

```bash
# 1. Control Plane 업그레이드
# terraform.tfvars에서 cluster_version 변경
eks_cluster_version = "1.29"

terraform plan
terraform apply

# 2. Node Group 업그레이드
# - Rolling update로 자동 진행
# - Pod Disruption Budget 확인

# 3. Add-ons 업그레이드
# - vpc-cni
# - coredns
# - kube-proxy
```

### RDS 인스턴스 크기 변경

```bash
# terraform.tfvars 수정
rds_instance_class = "db.r6i.2xlarge"

# Apply (자동으로 Modify 실행)
terraform plan
terraform apply

# 참고: Multi-AZ의 경우 Downtime 최소화
```

## 롤백

### Terraform State 롤백

```bash
# 1. State 백업 확인
aws s3 ls s3://gympt-tfstate-${ACCOUNT_ID}/dev/

# 2. 이전 State 다운로드
aws s3 cp \
  s3://gympt-tfstate-${ACCOUNT_ID}/dev/terraform.tfstate \
  terraform.tfstate.backup \
  --version-id VERSION_ID

# 3. State 복원
terraform state push terraform.tfstate.backup

# 4. 검증
terraform plan
```

### 리소스 롤백

**단일 리소스 재생성**:
```bash
# 1. 리소스 Taint
terraform taint module.eks.aws_eks_node_group.main["general"]

# 2. 재생성
terraform apply
```

**전체 인프라 재생성**:
```bash
# 주의: Dev 환경에서만 사용

# 1. 전체 삭제
terraform destroy

# 2. 재생성
terraform apply
```

### 긴급 롤백 시나리오

**EKS 업그레이드 롤백**:
```bash
# 1. 이전 버전으로 변경
eks_cluster_version = "1.28"

# 2. Apply
terraform apply

# 참고: Control Plane 다운그레이드는 불가능
# Node Group만 이전 버전으로 롤백 가능
```

**RDS 스냅샷 복원**:
```bash
# 1. 최근 스냅샷 확인
aws rds describe-db-snapshots \
  --db-instance-identifier gympt-dev-postgres \
  --query 'DBSnapshots[0].DBSnapshotIdentifier' \
  --output text

# 2. 새 인스턴스로 복원
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier gympt-dev-postgres-restored \
  --db-snapshot-identifier snapshot-id

# 3. Terraform State 수정
terraform import module.rds.aws_db_instance.main gympt-dev-postgres-restored
```

## 자동화 스크립트

### 전체 배포 스크립트

```bash
# Dev 환경 전체 배포
./scripts/deploy-infra-dev.sh

# Prod 환경 전체 배포
./scripts/deploy-infra-prod.sh
```

### 검증 스크립트

```bash
# 모든 모듈 검증
./scripts/validate-all.sh

# Plan 실행 (모든 환경)
./scripts/plan-all.sh

# Apply 실행 (모든 환경)
./scripts/apply-all.sh
```

### 백업 스크립트

```bash
# State 백업
./scripts/backup-state.sh

# 스냅샷 생성
./scripts/create-snapshots.sh dev
```

## 트러블슈팅

### 일반적인 문제

**State Lock 해제**:
```bash
# Lock 확인
aws dynamodb scan \
  --table-name gympt-tfstate-lock

# Lock 삭제 (주의!)
terraform force-unlock LOCK_ID
```

**Provider 플러그인 문제**:
```bash
# Provider 재설치
rm -rf .terraform
terraform init -upgrade
```

**리소스 Drift 감지**:
```bash
# Drift 확인
terraform plan -refresh-only

# Drift 수정
terraform apply -refresh-only
```

---

**다음**: [트러블슈팅](트러블슈팅.md) | [보안 설정](보안설정.md)
