# HashiCorp Boundary 가이드

Zero-Trust Bastion으로 내부 리소스(EKS, RDS 등)에 안전하게 접근하는 방법을 설명한다.

## 목차
- [개요](#개요)
- [아키텍처](#아키텍처)
- [Terraform 구성](#terraform-구성)
- [초기 배포](#초기-배포)
- [운영자 접속 방법](#운영자-접속-방법)
- [Target 관리](#target-관리)
- [트러블슈팅](#트러블슈팅)

---

## 개요

HashiCorp Boundary는 SSH 키/DB 비밀번호 없이 동적 자격증명과 세션 기록을 통해 내부 리소스에 대한 접근을 중앙 관리하는 Zero-Trust Access 플랫폼이다.

**도입 목적**:
- EKS 공개 API 엔드포인트를 `0.0.0.0/0`으로 열지 않고도 운영자 접근 허용
- RDS/Redis 접근 시 자격증명 공유 없이 개인 계정 기반 접근
- 모든 세션 감사 로그 자동 기록

---

## 아키텍처

```
인터넷
  │
  │ :9200 (API/UI), :9202 (Proxy)
  ▼
Boundary EC2 — Public Subnet (gympt-prod-boundary)
  ├── Controller  (9200, 9201)
  ├── Worker      (9202)
  └── PostgreSQL  (내부 — Controller 백엔드 DB)
        │
        │ KMS (root / worker-auth / recovery)
        ▼
   AWS KMS (3개 키)
        │
        │ 세션 터널
        ▼
Private 리소스
  ├── EKS API Server         (443)
  ├── RDS PostgreSQL         (5432)
  └── ElastiCache Redis      (6379)
```

---

## Terraform 구성

### 모듈 위치

```
terraform/modules/boundary/
├── main.tf                          # EC2, KMS, IAM, SG
├── variables.tf
├── outputs.tf
└── templates/
    └── setup-boundary.sh.tpl        # user data — PostgreSQL + Boundary 설치
```

### prod 환경 설정 위치

```hcl
# terraform/environments/prod/main.tf
module "boundary" {
  source = "../../modules/boundary"

  project_name        = local.project_name      # "gympt"
  env                 = local.env               # "prod"
  aws_region          = local.aws_region        # "ap-northeast-2"
  vpc_id              = module.vpc.vpc_id
  public_subnet_id    = module.vpc.public_subnet_ids[0]
  instance_type       = "t3.medium"
  db_password         = var.boundary_db_password
  allowed_cidr_blocks = ["0.0.0.0/0"]           # TODO: 운영 IP로 제한
  common_tags         = local.common_tags
}
```

### 변수

`boundary_db_password`는 `terraform/environments/prod/variables.tf`에 정의되어 있으며 `sensitive = true`이다.

```bash
# 환경변수로 전달
export TF_VAR_boundary_db_password="your-password"

# 또는 terraform.tfvars (gitignore 처리 필수)
boundary_db_password = "your-password"
```

### 출력값

```bash
terraform output boundary_api_endpoint   # http://<IP>:9200
terraform output boundary_public_ip      # EC2 퍼블릭 IP
terraform output boundary_instance_id    # EC2 인스턴스 ID
```

---

## 초기 배포

### 1. Apply

```bash
cd terraform/environments/prod
terraform init
terraform apply -target=module.boundary
```

### 2. 초기화 완료 확인

EC2 기동 후 user data 스크립트가 자동 실행된다. 완료까지 약 3~5분 소요.

```bash
# SSM으로 접속
aws ssm start-session \
  --target $(terraform output -raw boundary_instance_id) \
  --region ap-northeast-2

# 설치 로그
tail -50 /var/log/boundary-setup.log

# 초기화 로그 (admin 비밀번호 포함)
cat /var/log/boundary-init.log

# 서비스 상태
systemctl status boundary postgresql
```

### 3. 초기 로그인

```bash
export BOUNDARY_ADDR="http://$(terraform output -raw boundary_public_ip):9200"

boundary authenticate password \
  -auth-method-id=<log에서 확인한 auth_method_id> \
  -login-name=admin
```

### 4. 초기 비밀번호 변경 (필수)

```bash
boundary accounts change-password -id=<account_id>
```

---

## 운영자 접속 방법

### kubectl (EKS)

```bash
# 1. Boundary 세션 시작
boundary connect \
  -target-id=<eks_target_id> \
  -listen-port=16443 &

# 2. kubeconfig에서 server 주소 재지정
kubectl \
  --server=https://127.0.0.1:16443 \
  --insecure-skip-tls-verify \
  get nodes

# 또는 kubeconfig 수정
kubectl config set-cluster gympt-prod-boundary \
  --server=https://127.0.0.1:16443 \
  --insecure-skip-tls-verify=true
```

### psql (RDS)

```bash
# 방법 1: Boundary postgres 커넥터 (자동 포트포워딩 + psql 실행)
boundary connect postgres \
  -target-id=<rds_target_id> \
  -dbname=gympt \
  -username=gymptadmin

# 방법 2: 수동 포트포워딩
boundary connect \
  -target-id=<rds_target_id> \
  -listen-port=15432 &

psql -h 127.0.0.1 -p 15432 -U gymptadmin -d gympt
```

### Redis

```bash
boundary connect \
  -target-id=<redis_target_id> \
  -listen-port=16379 &

redis-cli -h 127.0.0.1 -p 16379
```

---

## Target 관리

### EKS API Target 등록 예시

```bash
# Org → Project 생성
boundary scopes create -scope-id=global -name="gympt"
boundary scopes create -scope-id=<org_id> -name="prod"

# 호스트 카탈로그
boundary host-catalogs create static -scope-id=<proj_id> -name="prod-hosts"

# EKS API 호스트
EKS_HOST=$(terraform -chdir=terraform/environments/prod output -raw eks_cluster_endpoint | sed 's|https://||')
boundary hosts create static \
  -host-catalog-id=<catalog_id> \
  -name="eks-api" \
  -address="$EKS_HOST"

# 호스트 셋
boundary host-sets create static -host-catalog-id=<catalog_id> -name="eks-set"
boundary host-sets add-hosts -id=<set_id> -host=<host_id>

# Target
boundary targets create tcp \
  -scope-id=<proj_id> \
  -name="eks-api" \
  -default-port=443 \
  -host-source-id=<set_id>
```

### RDS Target 등록 예시

```bash
RDS_HOST=$(terraform -chdir=terraform/environments/prod output -raw rds_endpoint | cut -d: -f1)
boundary hosts create static \
  -host-catalog-id=<catalog_id> \
  -name="rds-postgres" \
  -address="$RDS_HOST"

boundary targets create tcp \
  -scope-id=<proj_id> \
  -name="rds-postgres" \
  -default-port=5432 \
  -host-source-id=<set_id>
```

---

## 트러블슈팅

### Boundary 서비스가 시작되지 않음

```bash
journalctl -u boundary -n 50 --no-pager
```

원인: PostgreSQL이 아직 기동 중이거나 DB 초기화가 완료되지 않은 경우.

```bash
systemctl restart postgresql
systemctl restart boundary
```

### DB 초기화 실패

`/var/log/boundary-init.log`에서 에러 확인 후 수동 재시도:

```bash
sudo -u boundary boundary database init \
  -config=/etc/boundary.d/boundary.hcl
```

### user data 스크립트 재실행

EC2 재기동 시 user data는 자동으로 재실행되지 않는다. 수동으로 실행하려면:

```bash
sudo bash /var/lib/cloud/instance/scripts/part-001
```

### KMS 접근 오류

EC2 IAM Role에 KMS 접근 권한이 있는지 확인:

```bash
aws kms describe-key --key-id <kms_key_id> --region ap-northeast-2
```

---

## 보안 후속 조치

| 항목 | 설명 | 우선순위 |
|------|------|---------|
| `allowed_cidr_blocks` 제한 | `0.0.0.0/0` → 사무실/VPN IP | 높음 |
| admin 비밀번호 변경 | 초기화 직후 즉시 변경 | 높음 |
| 초기화 로그 삭제 | `/var/log/boundary-init.log`의 자격증명 제거 | 높음 |
| TLS 적용 | ALB HTTPS 또는 Let's Encrypt | 중간 |
| 운영자별 계정 분리 | 팀원 개별 Boundary 계정 생성 | 중간 |
| 세션 녹화 설정 | Boundary Session Recording 활성화 | 낮음 |

---

**관련 문서**: [보안설정.md](보안설정.md) | [배포절차.md](배포절차.md) | [모듈참조.md](모듈참조.md)
