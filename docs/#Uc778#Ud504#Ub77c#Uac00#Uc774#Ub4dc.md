# GYMPT 인프라 가이드

## 목차
- [개요](#개요)
- [아키텍처](#아키텍처)
- [환경 구성](#환경-구성)
- [네트워크 설계](#네트워크-설계)
- [보안 설계](#보안-설계)
- [고가용성](#고가용성)

## 개요

GYMPT 인프라는 AWS 클라우드 네이티브 아키텍처를 기반으로 설계되었습니다.

### 핵심 원칙

1. **클라우드 네이티브**: AWS 관리형 서비스 활용
2. **마이크로서비스**: 독립적으로 확장 가능한 서비스
3. **Infrastructure as Code**: Terraform으로 모든 인프라 관리
4. **보안 우선**: 최소 권한, 암호화, 감사 로깅
5. **자동화**: CI/CD, Auto Scaling, 자동 복구

### 기술 스택

- **컨테이너 오케스트레이션**: Amazon EKS (Kubernetes 1.28)
- **데이터베이스**: Amazon RDS PostgreSQL 15
- **캐시**: Amazon ElastiCache Redis 7
- **메시징**: Amazon SQS, EventBridge
- **스토리지**: Amazon S3, EBS
- **스트리밍**: Kinesis Video Streams
- **모니터링**: CloudWatch, Prometheus, Grafana

## 아키텍처

### 전체 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│                         Internet                             │
└───────────────────────┬─────────────────────────────────────┘
                        │
            ┌───────────▼──────────┐
            │   Route 53 + WAF     │
            └───────────┬──────────┘
                        │
            ┌───────────▼──────────┐
            │   CloudFront CDN     │
            └───────────┬──────────┘
                        │
┌───────────────────────┼─────────────────────────────────────┐
│                   VPC (10.0.0.0/16)                         │
│                       │                                      │
│  ┌────────────────────▼────────────────┐                   │
│  │  Public Subnet (Multi-AZ)           │                   │
│  │  - Application Load Balancer        │                   │
│  │  - NAT Gateway                      │                   │
│  └────────────────────┬────────────────┘                   │
│                       │                                      │
│  ┌────────────────────▼────────────────┐                   │
│  │  Private Subnet (Multi-AZ)          │                   │
│  │  ┌──────────────────────────────┐   │                   │
│  │  │   Amazon EKS Cluster         │   │                   │
│  │  │  ┌─────────────────────────┐ │   │                   │
│  │  │  │ Backend API             │ │   │                   │
│  │  │  │ Agent Service           │ │   │                   │
│  │  │  │ Posture Analysis        │ │   │                   │
│  │  │  │ Report Service          │ │   │                   │
│  │  │  │ Remediation Worker      │ │   │                   │
│  │  │  └─────────────────────────┘ │   │                   │
│  │  └──────────────────────────────┘   │                   │
│  └────────────────────┬────────────────┘                   │
│                       │                                      │
│  ┌────────────────────▼────────────────┐                   │
│  │  Database Subnet (Multi-AZ)         │                   │
│  │  - RDS PostgreSQL (Multi-AZ)        │                   │
│  │  - ElastiCache Redis (Cluster)      │                   │
│  └─────────────────────────────────────┘                   │
└─────────────────────────────────────────────────────────────┘

External Services:
┌─────────────────────────────────────────────────────────────┐
│ S3 (Videos, Reports) │ SQS │ DynamoDB │ KVS │ Secrets Mgr   │
└─────────────────────────────────────────────────────────────┘
```

### 서비스 흐름

```
1. 사용자 요청
   → CloudFront → ALB → Backend API (EKS)
   
2. 비디오 업로드
   → S3 → EventBridge → Posture Analysis (EKS)
   
3. 실시간 스트리밍
   → KVS → Agent Service (EKS) → WebRTC
   
4. 자세 분석
   → SQS → Posture Analysis → DynamoDB/RDS
   
5. 보고서 생성
   → EventBridge → Report Service (EKS) → S3
```

## 환경 구성

### Dev 환경

**목적**: 개발 및 테스트

**특징**:
- 단일 또는 2-AZ 배포
- 소규모 인스턴스 (t3 시리즈)
- RDS Single-AZ
- Redis 단일 노드
- 백업 보관 7일

**리소스**:
```
VPC CIDR: 10.0.0.0/16
EKS Nodes: 2-10 nodes (t3.large)
RDS: db.t3.medium (Single-AZ)
Redis: cache.t3.medium (1 node)
NAT Gateway: 1개
```

**예상 비용**: $300-500/월

### Prod 환경

**목적**: 운영 서비스

**특징**:
- 3-AZ 고가용성
- 대규모 인스턴스 (c6i, r6i 시리즈)
- RDS Multi-AZ
- Redis 클러스터 (3 노드)
- 백업 보관 30일
- 자동 장애 조치

**리소스**:
```
VPC CIDR: 10.1.0.0/16
EKS Nodes: 5-30 nodes (c6i.xlarge)
RDS: db.r6i.xlarge (Multi-AZ)
Redis: cache.r6g.large (3 nodes)
NAT Gateway: 3개 (각 AZ)
```

**예상 비용**: $2,000-4,000/월

## 네트워크 설계

### VPC 구성

```
VPC: 10.0.0.0/16 (65,536 IPs)

Public Subnets (인터넷 접근 가능):
├── 10.0.1.0/24 (ap-northeast-2a) - 256 IPs
├── 10.0.2.0/24 (ap-northeast-2b) - 256 IPs
└── 10.0.3.0/24 (ap-northeast-2c) - 256 IPs

Private Subnets (NAT Gateway 경유):
├── 10.0.11.0/24 (ap-northeast-2a) - 256 IPs
├── 10.0.12.0/24 (ap-northeast-2b) - 256 IPs
└── 10.0.13.0/24 (ap-northeast-2c) - 256 IPs

Database Subnets (격리됨):
├── 10.0.21.0/24 (ap-northeast-2a) - 256 IPs
├── 10.0.22.0/24 (ap-northeast-2b) - 256 IPs
└── 10.0.23.0/24 (ap-northeast-2c) - 256 IPs
```

### 라우팅

**Public Subnet Route Table**:
```
Destination     Target
0.0.0.0/0       Internet Gateway
10.0.0.0/16     Local
```

**Private Subnet Route Table** (각 AZ):
```
Destination     Target
0.0.0.0/0       NAT Gateway (해당 AZ)
10.0.0.0/16     Local
S3 Endpoint     VPC Endpoint
DynamoDB EP     VPC Endpoint
```

**Database Subnet Route Table**:
```
Destination     Target
10.0.0.0/16     Local
(인터넷 접근 불가)
```

### VPC Endpoints

**Gateway Endpoints** (무료):
- S3
- DynamoDB

**Interface Endpoints** (시간당 과금):
- ECR API
- ECR Docker
- SSM
- SSM Messages
- EC2 Messages
- Secrets Manager

## 보안 설계

### 네트워크 보안

**Security Groups**:
```
1. ALB Security Group
   Inbound: 0.0.0.0/0:443 (HTTPS)
   Outbound: EKS Nodes:30000-32767

2. EKS Node Security Group
   Inbound: ALB:30000-32767, Self:All
   Outbound: All

3. RDS Security Group
   Inbound: EKS Nodes:5432
   Outbound: None

4. Redis Security Group
   Inbound: EKS Nodes:6379
   Outbound: None
```

**Network ACLs**:
- Public Subnet: Allow HTTP/HTTPS Inbound
- Private Subnet: Allow All within VPC
- Database Subnet: Allow only from Private Subnet

### IAM 보안

**IRSA (IAM Roles for Service Accounts)**:
```
각 EKS Pod는 전용 IAM 역할 사용:
- backend-api: S3, DynamoDB, Secrets Manager
- agent-service: KVS, EventBridge
- posture-analysis: S3, SQS, DynamoDB
- report-service: S3, Lambda
```

**최소 권한 원칙**:
- 필요한 리소스에만 접근
- 시간 제한 자격 증명
- 정기적인 권한 검토

### 데이터 보안

**저장 데이터 암호화**:
- RDS: KMS 암호화
- ElastiCache: At-rest 암호화
- S3: SSE-S3 또는 SSE-KMS
- EBS: 기본 암호화 활성화
- Secrets Manager: 자동 암호화

**전송 중 암호화**:
- ALB: TLS 1.2+
- RDS: SSL/TLS 강제
- ElastiCache: TLS 모드
- S3: HTTPS 전용

### 모니터링 및 감사

**CloudTrail**:
- 모든 API 호출 로깅
- S3 장기 보관
- CloudWatch Logs 실시간 분석

**VPC Flow Logs**:
- 모든 네트워크 트래픽 로깅
- 보안 이상 탐지
- Athena로 분석

**CloudWatch Alarms**:
- 보안 그룹 변경
- IAM 정책 변경
- 루트 계정 사용
- MFA 비활성화

## 고가용성

### Multi-AZ 배포

**EKS**:
- 3개 AZ에 노드 분산
- Pod Disruption Budget 설정
- Cluster Autoscaler / Karpenter

**RDS**:
- Multi-AZ 자동 장애 조치
- Read Replica (읽기 부하 분산)
- 자동 백업 (Point-in-Time Recovery)

**ElastiCache**:
- Redis Cluster 모드
- 자동 장애 조치
- 읽기 엔드포인트

### 자동 스케일링

**EKS Node Autoscaling**:
```yaml
# Karpenter Provisioner
apiVersion: karpenter.sh/v1alpha5
kind: Provisioner
spec:
  requirements:
    - key: karpenter.sh/capacity-type
      operator: In
      values: ["spot", "on-demand"]
  limits:
    resources:
      cpu: 1000
      memory: 1000Gi
```

**Application Autoscaling**:
```yaml
# Horizontal Pod Autoscaler
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
spec:
  minReplicas: 3
  maxReplicas: 30
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

### 백업 및 복구

**RDS 백업**:
- 자동 백업: 매일 (보관 7-30일)
- 스냅샷: 주간 (보관 90일)
- Cross-Region 복제 (Prod)

**S3 백업**:
- Versioning 활성화
- Lifecycle 정책 (Glacier 이동)
- Cross-Region 복제 (중요 데이터)

**Terraform State 백업**:
- S3 버전 관리
- DynamoDB 상태 잠금
- 정기 백업 스크립트

### 재해 복구 (DR)

**RTO (Recovery Time Objective)**: 1시간  
**RPO (Recovery Point Objective)**: 15분

**DR 절차**:
1. RDS 최신 스냅샷에서 복원
2. EKS 클러스터 재생성
3. 애플리케이션 배포
4. DNS 전환

---

**다음**: [모듈 참조](모듈참조.md) | [배포 절차](배포절차.md)
