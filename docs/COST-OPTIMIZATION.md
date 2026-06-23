# 비용 최적화 설계 (Cost Optimization)

> 목표: **하루 $10 이하** (예산 한도 대응)

## 1. 현황 분석

청구서 기준(2026-06-06, 하루 ~$69):

| 순위 | 항목 | 하루 | 비고 |
|---|---|---|---|
| 1 | GPU g4dn.xlarge | $15.53 | posture-analysis |
| 2 | RDS db.t3.large Multi-AZ | $10.75 | |
| 3 | vended logs (CloudWatch) | $10.35 | VPC Flow Logs 등 13.6GB/일 |
| 4 | EKS general t3.xlarge×2 | $9.98 | |
| 5 | VPC Endpoint ×24 | $7.49 | interface endpoint 과다 |
| 6 | ElastiCache Redis ×2 | $4.75 | |
| 7 | NAT Gateway ×2 | $2.83 | |
| 8 | EKS 클러스터 | $2.40 | 고정 (삭제 외 불가) |
| | EBS/ALB/IPv4/WAF 등 | ~$5 | |

**숨은 비용 주의**: vended logs($10), VPC Endpoint 24개($7.5), public IPv4($0.48) — 합 ~$18/일. 인스턴스만 보면 놓치기 쉬움.

## 2. 설계 원칙 — 두 축으로 분리

| 축 | 대상 | 방법 |
|---|---|---|
| **A. 상시 축소** | 구조적으로 과한 리소스 | 한 번 설정, 항상 적용 |
| **B. on/off** | 사용 시간만 필요한 리소스 | `down.sh`/`up.sh`로 켤 때만 과금 |

> ⚠️ `down.sh`(EKS 종료)만으로는 상시 비용(RDS/VPC endpoint/ElastiCache/NAT/vended ~$33/일)이 남아 $10 목표 미달. **상시 축소(축 A) 병행 필수.**

## 3. 축 A — 상시 축소 (한 번 설정)

| 항목 | 현재 | 조치 | 절감/일 |
|---|---|---|---|
| **VPC Endpoint** | 24개 | 필수만 유지(ECR api/dkr 등), S3는 Gateway endpoint(무료)로 | -$5 |
| **vended logs** | 13.6GB | VPC Flow Logs 끄기 또는 REJECT만/샘플링, 불필요 CloudWatch 로그 정리 | -$4 |
| **ElastiCache** | t3.medium ×2 | t3.micro ×1 (또는 스냅샷 후 재생성) | -$4 |
| **NAT Gateway** | 2개 | 1개 (가용성↓, 개발단계 허용) | -$1.4 |

→ 상시 축소만으로 **-$14/일**

## 4. 축 B — on/off (down.sh / up.sh)

### down.sh (종료) — 기존 + RDS 추가
```
[기존]
- ArgoCD auto-sync 중단
- HPA 삭제 + Deployment 0 replicas (워크로드 0)
- Karpenter 노드 drain
- general node group desiredSize=0
  → GPU(g4dn) 포함 모든 EKS 노드 회수

[추가]
- RDS 중지:
  aws rds stop-db-instance --db-instance-identifier gympt-prod-postgres --region ap-northeast-2
```

### up.sh (재개)
```
- general node group desiredSize=1 (또는 필요 수)
- ArgoCD auto-sync 복원 → Deployment/HPA 자동 재생성
- RDS 시작:
  aws rds start-db-instance --db-instance-identifier gympt-prod-postgres --region ap-northeast-2
- (Boundary 사용 시) EC2 start → ExecStartPre가 Route53 자동 갱신
```

## 5. 예상 비용

```
■ down 상태 (개발 안 함)
  EKS 클러스터       $2.40
  ElastiCache micro  $0.40
  VPC endpoint(필수) $2.00
  NAT ×1             $1.40
  vended(축소)       $1.00
  EBS                $0.50
  RDS (stop)         $0.00  (스토리지 ~$0.87/일만)
  ────────────────────────
  합계               ≈ $7.7/일   ✅ 목표 달성

■ up 상태 (개발 중)
  위 + Karpenter 노드(워크로드 분) + RDS start(시간 분)
  → 8시간 작업 시 대략 $12~15/일
```

## 6. 실행 우선순위 (효과/안전 순)

| 순위 | 작업 | 절감/일 | 안전도 | 시점 |
|---|---|---|---|---|
| 1 | vended logs 축소 (VPC Flow Logs) | -$4 | 안전 | 즉시 |
| 2 | VPC Endpoint 정리 (24→필수) | -$5 | 안전 | 즉시 |
| 3 | RDS stop을 down.sh에 추가 | -$10.75 | 개발 안 할 때 | 즉시 |
| 4 | ElastiCache micro/축소 | -$4 | 스냅샷 후 | 중간 |
| 5 | NAT 2→1 | -$1.4 | 가용성↓ | 중간 |

**1·2번(-$9/일)은 서비스 영향 없이 즉시 가능** → 가장 먼저.

## 7. 주의사항

- **RDS stop은 최대 7일** 후 AWS가 자동 시작 → 장기 미사용 시 재 stop 필요.
- **ElastiCache는 중지 불가** → 스냅샷 후 삭제/재생성, 또는 micro로 상시 운영.
- **EKS 전체 `terraform apply` 금지** — helm/k8s 리소스가 state 밖이라 재생성 충돌 위험. 좁은 `-target`만 사용.
- **RDS/Redis 자격증명 drift** (tfvars≠실제) → RDS/ElastiCache 모듈 전체 apply 금지(SG만 `-target`).
- `down.sh` 후 `node_min_size`는 다음 terraform apply 때 1로 복원됨 → 영구 0 원하면 `prod/main.tf`에서 `node_min_size = 0`.

