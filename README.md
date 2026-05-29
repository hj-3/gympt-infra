# GYMPT Infrastructure

Terraform 기반 AWS 인프라 코드

## 📋 개요

GYMPT 플랫폼의 전체 AWS 인프라를 Terraform으로 관리합니다.

### 주요 인프라
- 🌐 VPC 및 네트워킹
- ⚙️ EKS 클러스터 (Kubernetes)
- 💾 데이터베이스 (RDS, DynamoDB, ElastiCache)
- 📦 스토리지 (S3, ECR)
- 📨 메시징 (SQS, EventBridge)
- 🎬 스트리밍 (Kinesis Video Streams)
- 📊 모니터링 (CloudWatch, Athena)
- 🛡️ 보안 (IAM, Secrets Manager, HashiCorp Boundary)
- 🔐 접근 제어 (HashiCorp Boundary — Zero-Trust Bastion)

### Terraform 모듈 (26개)
모든 인프라 컴포넌트는 재사용 가능한 모듈로 구성되어 있습니다.

## 🏗️ 아키텍처

- **다중 환경**: dev, prod 완전 분리
- **고가용성**: Multi-AZ 배포
- **보안**: Private 서브넷, IRSA, Secrets Manager
- **확장성**: Auto Scaling, Karpenter
- **관찰성**: Prometheus, Grafana, CloudWatch

## 🚀 빠른 시작

### 사전 요구사항
- Terraform 1.5+
- AWS CLI
- kubectl (EKS 접근용)

### 초기 설정

```bash
# 1. S3 백엔드 초기화
./scripts/init-backend.sh

# 2. Dev 환경 배포
./scripts/deploy-infra-dev.sh

# 3. Kubeconfig 설정
./scripts/get-kubeconfig.sh dev

# 4. 리소스 확인
./scripts/utilities/check-resources.sh dev
```

## 📖 문서

- [인프라 가이드](docs/인프라가이드.md)
- [모듈 참조](docs/모듈참조.md)
- [배포 절차](docs/배포절차.md)
- [보안 설정](docs/보안설정.md)
- [트러블슈팅](docs/트러블슈팅.md)

## 🛠️ 주요 스크립트

- `init-backend.sh` - Terraform 백엔드 초기화
- `deploy-infra-dev.sh` - Dev 환경 배포
- `get-kubeconfig.sh` - EKS 접근 설정
- `backup-state.sh` - State 백업
- `db-tunnel.sh` - RDS 터널 (SSM)

## 📦 Terraform 모듈

### 네트워크
- vpc - VPC, 서브넷, NAT Gateway
- security - Security Groups, NACLs

### 컴퓨팅
- eks - EKS 클러스터
- karpenter - 노드 자동 확장

### 데이터베이스
- rds - PostgreSQL
- dynamodb - NoSQL 테이블
- elasticache - Redis

### 스토리지
- s3 - 객체 스토리지
- ecr - 컨테이너 레지스트리

### 메시징
- sqs - 메시지 큐
- eventbridge - 이벤트 버스

### 서버리스
- lambda - Lambda 함수

### 스트리밍
- kvs - Kinesis Video Streams

### 모니터링
- cloudwatch - 메트릭 및 로그
- athena - 로그 분석
- glue - 데이터 카탈로그
- cloudtrail - 감사 로깅

### 보안
- iam - IAM 역할 및 정책
- waf - Web Application Firewall

### AI/ML
- bedrock - AI 모델 접근

### 스트리밍
- kvs - Kinesis Video Streams (WebRTC)
  - **수동 생성 필요**: WebRTC Signaling Channel은 AWS CLI로 생성 (상세: [docs/KVS_SETUP.md](docs/KVS_SETUP.md))

## 🔒 보안

- IRSA (IAM Roles for Service Accounts)
- Secrets Manager 통합
- SSM Session Manager (Bastion 불필요)
- Private 서브넷 배치
- 암호화 (at-rest, in-transit)

## 💰 비용 최적화

- Spot 인스턴스 지원
- Auto Scaling
- S3 Lifecycle 정책
- Reserved Instances 권장
- 리소스 태깅

## 🤝 기여하기

[CONTRIBUTING.md](CONTRIBUTING.md) 참고

---

---

## 📦 버전

**Current Version:** `0.1.0`

**Changelog:** [CHANGELOG.md](../CHANGELOG.md)

---

**상태**: Production Ready ✅  
**마지막 업데이트**: 2026-05-25

## 📚 추가 문서

- [KVS WebRTC 설정 가이드](docs/KVS_SETUP.md) - Kinesis Video Streams 초기 설정
- [HashiCorp Boundary 설정 가이드](docs/Boundary가이드.md) - Zero-Trust Bastion 설정 및 운영

---

## 🔄 변경 이력

### 2026-05-29

#### 신규 모듈

| 모듈 | 위치 | 설명 |
|------|------|------|
| `boundary` | `terraform/modules/boundary` | HashiCorp Boundary + PostgreSQL EC2 인스턴스. Zero-Trust Bastion으로 EKS/RDS 접근을 제어한다. KMS 3개(root/worker-auth/recovery), IAM Role(SSM+KMS), Security Group 포함. |

#### 보안 개선

| 항목 | 변경 전 | 변경 후 | 이유 |
|------|---------|---------|------|
| WAF 모듈 제거 | `terraform/modules/waf` 존재, Regional WAF | 모듈 삭제 — CloudFront 레벨에서 WAF 직접 연결 예정 | CloudFront WAF(CLOUDFRONT scope)로 통합하여 중복 제거 |
| dev RDS 패스워드 | `master_password = "changeme123"` 하드코딩 | `var.rds_master_password` 변수 참조 | 소스코드 자격증명 노출 방지 |
| EKS API 공개 접근 | `public_access_cidrs` 기본값 `0.0.0.0/0` | 모듈 기본값 제거 — 환경별 명시 강제 | 미설정 시 전세계 노출 방지 |
| IAM Secrets Manager 경로 | `gympt-prod/*` (대시) | `gympt/prod/*` (슬래시) | External Secrets 실제 경로(`gympt/prod/database` 등)와 일치시킴 |
| IAM SSM Parameter 경로 | `gympt-prod/*` (대시) | `gympt/prod/*` (슬래시) | 동일 — 경로 불일치로 External Secrets 권한 거부 버그 수정 |

#### GitHub Actions OIDC 개선

| 환경 | 변경 내용 |
|------|----------|
| dev | `allowed_branches`에 `"dev"` 추가 (기존: `["develop"]` → `["dev", "develop"]`). `create_app_role = true` 명시. |
| prod | `create_app_role = true` 명시. |

#### prod EKS 퍼블릭 접근 임시 활성화

```hcl
# terraform/environments/prod/main.tf
enable_public_access = true
public_access_cidrs  = ["0.0.0.0/0"]  # TODO: restrict to operator IPs after recovery
```

> VPN/Bastion 구성 완료 후 `enable_public_access = false` 또는 특정 IP로 제한 예정.
