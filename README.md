# GYMPT Infrastructure

> GYMPT 플랫폼을 위한 Terraform 기반 Infrastructure as Code

[![Terraform](https://img.shields.io/badge/Terraform-1.7+-purple)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-EKS%20%7C%20RDS%20%7C%20DynamoDB-orange)](https://aws.amazon.com/)

---

## 📋 개요

GYMPT 플랫폼을 위한 Infrastructure as Code. Terraform을 사용하여 완전한 AWS 클라우드 인프라를 프로비저닝합니다.

### Athena / Glue 로그 분석

Terraform은 중앙 S3 로그 버킷의 주요 보안/운영 로그를 Athena로 조회할 수 있도록 Glue Catalog Table을 생성합니다.

- `alb_access_logs`: `alb-access-logs/` (partition projection)
- `cloudfront_access_logs`: `cloudfront-logs/`
- `cloudtrail_logs`: `cloudtrail/`
- `inspector_findings`: `inspector-findings/` (partition projection)
- `s3_access_logs`: `s3-access-logs/`
- `vpc_flow_logs`: `vpc-flow-logs/` (partition projection)
- `waf_alb_logs`: `waf-logs/alb/` (partition projection)
- `waf_cloudfront_logs`: `waf-logs/cloudfront/` (partition projection)

`AWSLogs/` prefix는 별도 CloudTrail 계열 경로로 두고, 이 모듈에서는 제외합니다.

Athena 쿼리 결과는 Athena results S3 bucket의 `athena-results/` prefix에 저장됩니다. 기존 리소스를 팀원이 각자 `terraform import`하지 않고, Terraform 코드로 새 Glue table을 생성해 state 충돌을 피합니다.

Grafana는 `grafana-athena-datasource`와 `gympt-prod-grafana-athena` IRSA role로 Athena/Glue/S3 로그를 조회합니다.

### CloudWatch 알림 체계

2026-06-24 기준 prod는 AWS 리소스 경보를 CloudWatch Alarm → SNS → AWS Chatbot → Slack 경로로 보냅니다.

- **운영 알림 채널**: Slack channel `C0B6C0F1JB0`
- **보안 알림 채널**: Slack channel `C0B8L829W92`
- **보안 이벤트**: CloudTrail root activity, 콘솔 로그인 실패/MFA 미사용, IAM/SG/Trail/S3 정책 변경은 보안 SNS topic과 security-monitor Lambda 양쪽으로 전달
- **Billing/Cost 알람**: 회사 계정 권한 제약으로 Terraform 관리 대상에서 제외
- **S3 request metrics**: 사용자 요청 경로인 FE bucket(`gympt-fe-deploy-<account_id>`)과 media bucket만 활성화

최종 CloudWatch 경보 범위:

| 영역 | 경보 대상 |
|---|---|
| EKS/노드 | CPU, memory, node filesystem, ContainerInsights 기반 노드 지표 |
| ALB | target 5xx, ALB 5xx, unhealthy host, target response time, rejected connection, TLS negotiation error |
| CloudFront | `modules/cloudfront-monitoring`에서 us-east-1 provider alias로 5xx/4xx/total error rate, origin latency, request spike 관리 |
| RDS PostgreSQL | CPU, free storage, free memory, DB connections, read/write latency, read/write IOPS, deadlocks |
| Lambda | errors, duration, throttles, concurrent executions, async event age, DLQ/destination delivery failure |
| SQS | oldest message age, visible messages, in-flight messages, DLQ messages, receive/delete imbalance |
| DynamoDB | system errors, user errors, read/write throttles, transaction conflicts, consumed read/write spike |
| ElastiCache | CPU, memory, evictions, current connections, engine CPU, swap usage, replication lag |
| S3 | bucket size/object count, 4xx/5xx request errors, first-byte latency, request spike |
| WAF | blocked, counted, CAPTCHA, challenge request spike |
| KVS | PutMedia/GetMedia errors, incoming bytes low; active session peak은 GitOps PrometheusRule에서 관리 |
| EventBridge | failed invocations, throttled rules, dead-letter invocations |
| Inspector | HIGH/CRITICAL findings → Firehose/S3 및 SNS/Chatbot |
| Athena/Glue | Athena query failures, processed bytes spike |

### 빠른 배포

```bash
cd gympt-infra
../scripts/setup-cluster.sh prod
```

전체 README 내용은 [저장소에서 확인](https://github.com/hj-3/gympt-infra)

---

**저장소**: https://github.com/hj-3/gympt-infra

### 보안 설정 현황

**감사 및 로깅**
- **CloudTrail**: multi-region, log file validation, KMS CMK 암호화(`alias/gympt-prod-cloudtrail`), S3 적재
- **EKS control plane 로그**: OFF (`enabled_cluster_log_types = []`) — 시연 시 수동 on
- **CloudWatch 로그 보존**: EKS control plane 로그 그룹 retention 1일

**AI 보안관제 시스템**
- **구성**: EventBridge → Lambda → Bedrock (Claude Haiku 4.5) → Slack
- **실시간 감지**: CloudTrail 보안 이벤트 (IAM·SG·Trail·S3 정책 변경 등 20종), MFA 없는 콘솔 로그인
- **정기 스캔**: 30분 간격으로 WAF·Inspector·VPC Flow·S3·ALB 로그 Athena 분석
- **알림**: 위협 레벨(CRITICAL/HIGH/MEDIUM/LOW) 분류 후 Slack `#security-alerts` 채널 발송
- **Slack webhook**: Secrets Manager `gympt/prod/slack/security-webhook-url` 참조
- **운영 파라미터**: Lambda 환경변수로 코드 수정 없이 조정 가능 (콘솔 즉시 반영)

| 환경변수 | 기본값 | 설명 |
|---|---|---|
| `VPC_FLOW_REJECT_THRESHOLD` | 10 | VPC Flow REJECT 건수 임계값 |
| `VPC_FLOW_WINDOW_MINUTES` | 30 | VPC Flow 스캔 윈도우 (분) |
| `WAF_BLOCK_THRESHOLD` | 5 | WAF 동일 IP 차단 건수 임계값 |
| `S3_ERROR_THRESHOLD` | 5 | S3 에러 응답 건수 임계값 |
| `ALB_ERROR_THRESHOLD` | 10 | ALB 4xx/5xx 에러 건수 임계값 |
| `SCHEDULE_MIN_LEVEL` | HIGH | 정기 스캔 알람 최소 위협 레벨 |

**네트워크 격리**
- **VPC Endpoints SG**: egress `0.0.0.0/0` → VPC CIDR(`10.0.0.0/16`)으로 제한

**IRSA 최소 권한**
- **ECR Pull**: 노드 역할 `AmazonEC2ContainerRegistryReadOnly` 제거 → `gympt-prod/*` 레포 한정 커스텀 정책
- **IMDSv2 hop limit**: Karpenter EC2NodeClass `httpPutResponseHopLimit: 1` — 파드의 노드 IMDS 접근 차단
- **agent-service**: Bedrock `InvokeAgent` → `agent/WPQ0RESSZS` 한정, `Retrieve` → 계정 KB 한정, DynamoDB → `agent_interactions` 테이블 전용
- **posture-analysis-service**: S3 → `media` 버킷 한정(`PutObject`/`GetObject`/`ListBucket`), DynamoDB → `posture_events` 테이블 전용, KVS Signaling → `prod-live-sessions-signaling` 채널 전용

**정리**
- **remediation-worker**: ECR 레포, IAM 역할/정책, Terraform 코드, K8s 리소스 전체 제거 (Karpenter/HPA/ArgoCD로 기능 대체)

**최종 업데이트**: 2026-06-24
