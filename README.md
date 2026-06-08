# GYMPT Infrastructure

> GYMPT 플랫폼을 위한 Terraform 기반 Infrastructure as Code

[![Terraform](https://img.shields.io/badge/Terraform-1.7+-purple)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-EKS%20%7C%20RDS%20%7C%20DynamoDB-orange)](https://aws.amazon.com/)

---

## 📋 개요

GYMPT 플랫폼을 위한 Infrastructure as Code. Terraform을 사용하여 완전한 AWS 클라우드 인프라를 프로비저닝합니다.

### Athena / Glue 로그 분석

Terraform은 중앙 S3 로그 버킷의 주요 보안/운영 로그를 Athena로 조회할 수 있도록 Glue Catalog Table을 생성합니다.

- `alb_access_logs`: `alb-access-logs/`
- `cloudfront_access_logs`: `cloudfront-logs/`
- `cloudtrail_logs`: `cloudtrail/`
- `inspector_findings`: `inspector-findings/` (partition projection)
- `s3_access_logs`: `s3-access-logs/`
- `vpc_flow_logs`: `vpc-flow-logs/`
- `waf_alb_logs`: `waf-logs/alb/` (partition projection)
- `waf_cloudfront_logs`: `waf-logs/cloudfront/` (partition projection)

`AWSLogs/` prefix는 별도 CloudTrail 계열 경로로 두고, 이 모듈에서는 제외합니다.

Athena 쿼리 결과는 Athena results S3 bucket의 `athena-results/` prefix에 저장됩니다. 기존 리소스를 팀원이 각자 `terraform import`하지 않고, Terraform 코드로 새 Glue table을 생성해 state 충돌을 피합니다.

Grafana는 `grafana-athena-datasource`와 `gympt-prod-grafana-athena` IRSA role로 Athena/Glue/S3 로그를 조회합니다.

### 빠른 배포

```bash
cd gympt-infra
../scripts/setup-cluster.sh prod
```

전체 README 내용은 [저장소에서 확인](https://github.com/hj-3/gympt-infra)

---

**저장소**: https://github.com/hj-3/gympt-infra

**최종 업데이트**: 2026-06-08
