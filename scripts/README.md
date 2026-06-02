# GYMPT Infrastructure Scripts

> 인프라 관리를 위한 자동화 스크립트

---

## 📋 핵심 스크립트

### 1. init-backend.sh

**용도**: Terraform 백엔드 초기화 (S3 버킷 및 DynamoDB 테이블)

**사용법**:
```bash
./scripts/init-backend.sh
```

**수행 작업**:
- S3 버킷 생성 (`gympt-tfstate-{ACCOUNT_ID}`)
- DynamoDB 락 테이블 생성 (`gympt-tfstate-lock`)
- 버전 관리 활성화

**언제 사용**:
- 최초 1회 (새 환경 구축 시)
- Terraform 백엔드가 없을 때

---

### 2. get-kubeconfig.sh

**용도**: EKS 클러스터 kubeconfig 설정

**사용법**:
```bash
./scripts/get-kubeconfig.sh prod
./scripts/get-kubeconfig.sh dev
```

**수행 작업**:
- AWS EKS kubeconfig 업데이트
- kubectl 컨텍스트 설정
- 연결 테스트

**언제 사용**:
- EKS 클러스터 배포 후
- kubectl 연결이 필요할 때

---

### 3. db-tunnel.sh

**용도**: RDS PostgreSQL SSH 터널 설정

**사용법**:
```bash
./scripts/db-tunnel.sh prod
./scripts/db-tunnel.sh dev
```

**수행 작업**:
- Bastion 호스트를 통한 SSH 터널 생성
- 로컬 포트 5432로 RDS 연결
- 안전한 데이터베이스 접근

**언제 사용**:
- 로컬에서 RDS 직접 접근 필요 시
- 데이터베이스 마이그레이션
- 디버깅

**연결 후**:
```bash
# 다른 터미널에서
psql -h localhost -p 5432 -U gymptadmin -d gympt
```

---

### 4. check-project.sh

**용도**: 인프라 프로젝트 구조 및 설정 검증

**사용법**:
```bash
./scripts/check-project.sh
```

**검증 항목**:
- Terraform 파일 구조
- 필수 변수 정의
- 모듈 의존성
- 파일 권한

---

## 🚀 일반적인 사용 순서

### 신규 환경 구축

```bash
# 1. Terraform 백엔드 초기화
./scripts/init-backend.sh

# 2. Terraform 초기화 및 배포
cd terraform/environments/prod
terraform init \
  -backend-config="bucket=gympt-tfstate-$(aws sts get-caller-identity --query Account --output text)" \
  -backend-config="key=prod/terraform.tfstate" \
  -backend-config="region=ap-northeast-2" \
  -backend-config="dynamodb_table=gympt-tfstate-lock"

terraform apply -var-file=terraform.tfvars

# 3. kubeconfig 설정
cd ../../..
./scripts/get-kubeconfig.sh prod

# 4. 배포 검증
kubectl get nodes
```

### 데이터베이스 접근

```bash
# 터널 시작
./scripts/db-tunnel.sh prod

# 다른 터미널에서 연결
psql -h localhost -p 5432 -U gymptadmin -d gympt
```

---

## 📁 Utilities 디렉토리

`utilities/` 디렉토리에는 보조 스크립트들이 있습니다:

```bash
ls scripts/utilities/
```

---

## 📦 아카이브된 스크립트

다음 스크립트들은 `archive/`로 이동되었습니다:

| 스크립트 | 이동 사유 |
|---------|----------|
| **apply-all.sh** | 루트 setup-cluster.sh로 통합 |
| **backup-state.sh** | S3 버전 관리로 자동화 |
| **deploy-infra-dev.sh** | 루트 setup-cluster.sh로 통합 |
| **destroy-all.sh** | terraform destroy로 충분 |
| **plan-all.sh** | terraform plan으로 충분 |
| **setup-secrets.sh** | AWS Secrets Manager로 관리 |
| **validate-all.sh** | terraform validate로 충분 |

**아카이브 접근**:
```bash
ls scripts/archive/
```

---

## 🔧 트러블슈팅

### init-backend.sh 실패

```bash
# 수동으로 백엔드 생성
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws s3 mb s3://gympt-tfstate-${ACCOUNT_ID} --region ap-northeast-2

aws dynamodb create-table \
  --table-name gympt-tfstate-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ap-northeast-2
```

### get-kubeconfig.sh 실패

```bash
# 수동으로 kubeconfig 설정
aws eks update-kubeconfig \
  --name gympt-prod-eks \
  --region ap-northeast-2

# 연결 테스트
kubectl get nodes
```

### db-tunnel.sh 실패

```bash
# Bastion 호스트 확인
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=gympt-prod-bastion" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name,PublicIpAddress]'

# 수동 터널
ssh -i ~/.ssh/gympt-prod.pem -L 5432:RDS_ENDPOINT:5432 ubuntu@BASTION_IP
```

---

## 📖 관련 문서

- **[../README.md](../README.md)** - 인프라 개요
- **[../../DEPLOYMENT_GUIDE.md](../../DEPLOYMENT_GUIDE.md)** - 완전한 배포 가이드
- **[../../scripts/README.md](../../scripts/README.md)** - 루트 스크립트 가이드

---

**최종 업데이트**: 2026-06-02  
**관리**: Infrastructure Team
