# GymPT Infrastructure - Terraform

## Overview

Terraform infrastructure as code for the GymPT platform on AWS.

**Architecture:**
- Multi-AZ VPC with public/private subnets
- EKS cluster with Karpenter autoscaling
- RDS PostgreSQL for relational data
- DynamoDB for high-throughput workloads
- ElastiCache Redis for caching
- S3 for object storage
- CloudFront for content delivery
- Multiple SQS queues for async processing
- Lambda functions for serverless compute
- WAF for security
- CloudTrail for audit logging

## Directory Structure

```
terraform/
├── modules/                  # Reusable Terraform modules
│   ├── vpc/                 # VPC, subnets, NAT, VPC endpoints
│   ├── eks/                 # EKS cluster, node groups
│   ├── ecr/                 # ECR repositories
│   ├── rds/                 # PostgreSQL RDS
│   ├── dynamodb/            # DynamoDB tables
│   ├── elasticache/         # Redis cluster
│   ├── s3/                  # S3 buckets
│   ├── cloudfront/          # CloudFront distribution
│   ├── sqs/                 # SQS queues
│   ├── eventbridge/         # EventBridge rules
│   ├── lambda/              # Lambda functions
│   ├── waf/                 # WAF Web ACLs
│   ├── iam/                 # IAM roles and policies
│   ├── karpenter/           # Karpenter provisioners
│   ├── cloudwatch/          # CloudWatch alarms
│   ├── cloudtrail/          # CloudTrail configuration
│   ├── athena/              # Athena workgroups
│   └── glue/                # Glue data catalog
└── environments/
    ├── dev/                 # Development environment
    │   ├── main.tf          # Main configuration
    │   ├── outputs.tf       # Output values
    │   └── terraform.tfvars # Variable values
    └── prod/                # Production environment
        ├── main.tf
        ├── outputs.tf
        └── terraform.tfvars
```

## Prerequisites

### 1. Install Tools

```bash
# Terraform
brew install terraform  # macOS
# or
wget https://releases.hashicorp.com/terraform/1.7.0/terraform_1.7.0_linux_amd64.zip

# AWS CLI
brew install awscli
```

### 2. AWS Credentials

Configure AWS CLI with appropriate credentials:

```bash
aws configure
# AWS Access Key ID: YOUR_KEY
# AWS Secret Access Key: YOUR_SECRET
# Default region: ap-northeast-2
```

Or use AWS SSO:

```bash
aws sso login --profile gympt-dev
export AWS_PROFILE=gympt-dev
```

### 3. Create Terraform State Backend

**One-time setup per AWS account:**

```bash
# Create S3 bucket for state
aws s3 mb s3://gympt-terraform-state --region ap-northeast-2

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket gympt-terraform-state \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket gympt-terraform-state \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      },
      "BucketKeyEnabled": true
    }]
  }'

# Block public access
aws s3api put-public-access-block \
  --bucket gympt-terraform-state \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name gympt-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ap-northeast-2
```

## Usage

### Initialize Environment

```bash
# Navigate to environment
cd terraform/environments/dev

# Initialize Terraform with backend configuration
terraform init \
  -backend-config="bucket=gympt-terraform-state" \
  -backend-config="key=dev/terraform.tfstate" \
  -backend-config="region=ap-northeast-2" \
  -backend-config="dynamodb_table=gympt-terraform-locks"
```

### Plan Changes

```bash
# See what will be created/changed
terraform plan

# Save plan to file
terraform plan -out=tfplan
```

### Apply Changes

```bash
# Apply saved plan
terraform apply tfplan

# Or apply directly (with confirmation)
terraform apply

# Auto-approve (dangerous, use with caution)
terraform apply -auto-approve
```

### Destroy Resources

```bash
# Destroy all resources (DANGEROUS!)
terraform destroy

# Destroy specific resource
terraform destroy -target=module.eks
```

## Environment Configuration

### Development (dev)

**Location:** `environments/dev/`

**Configuration:**
- VPC CIDR: `10.0.0.0/16`
- EKS nodes: `2-10` t3.large instances
- RDS: db.t3.micro, single-AZ
- Redis: cache.t3.micro
- S3 versioning: Enabled
- Multi-AZ: No (cost optimization)
- Backup retention: 7 days

**Purpose:** Development and testing

### Production (prod)

**Location:** `environments/prod/`

**Configuration:**
- VPC CIDR: `10.1.0.0/16`
- EKS nodes: `3-20` t3.xlarge instances
- RDS: db.t3.large, multi-AZ
- Redis: cache.t3.medium, cluster mode
- S3 versioning: Enabled
- Multi-AZ: Yes
- Backup retention: 30 days

**Purpose:** Production workloads

## Naming Convention

All resources follow this naming pattern:

```
{project_name}-{env}-{resource_type}-{optional_suffix}
```

**Examples:**
- VPC: `gympt-dev-vpc`
- EKS: `gympt-dev-eks`
- RDS: `gympt-dev-rds`
- S3: `gympt-dev-frontend-{account_id}`

**Why account ID suffix for S3?**
S3 bucket names must be globally unique across all AWS accounts. Adding account ID ensures uniqueness.

## Module Usage Examples

### VPC Module

```hcl
module "vpc" {
  source = "../../modules/vpc"

  project_name = "gympt"
  env          = "dev"
  aws_region   = "ap-northeast-2"
  vpc_cidr     = "10.0.0.0/16"
  
  common_tags = {
    Project     = "gympt"
    Environment = "dev"
  }
}
```

### EKS Module

```hcl
module "eks" {
  source = "../../modules/eks"

  project_name         = "gympt"
  env                  = "dev"
  vpc_id               = module.vpc.vpc_id
  private_subnet_ids   = module.vpc.private_app_subnet_ids
  cluster_version      = "1.28"
  node_desired_size    = 2
  enable_gpu_node_group = true
}
```

### S3 Module

```hcl
module "s3" {
  source = "../../modules/s3"

  project_name = "gympt"
  env          = "dev"
  account_id   = "123456789012"  # Ensures unique bucket names
}
```

## Common Operations

### Add New Resource

1. **Create in module:**

```bash
cd terraform/modules/my-module
touch main.tf variables.tf outputs.tf
```

2. **Use in environment:**

```hcl
# In environments/dev/main.tf
module "my_module" {
  source = "../../modules/my-module"
  
  project_name = local.project_name
  env          = local.env
}
```

3. **Apply changes:**

```bash
cd environments/dev
terraform init
terraform plan
terraform apply
```

### Update Existing Resource

1. **Edit module or environment file**
2. **Plan to see changes:**

```bash
terraform plan
```

3. **Apply if changes look correct:**

```bash
terraform apply
```

### Import Existing Resource

If resource was created manually:

```bash
# Import VPC
terraform import module.vpc.aws_vpc.main vpc-12345678

# Import RDS
terraform import module.rds.aws_db_instance.main gympt-dev-rds
```

### View State

```bash
# List resources
terraform state list

# Show specific resource
terraform state show module.vpc.aws_vpc.main

# Pull current state
terraform state pull > state.json
```

### Migrate State

```bash
# Move resource to different module
terraform state mv module.old.aws_instance.example module.new.aws_instance.example

# Remove resource from state (doesn't delete actual resource)
terraform state rm module.eks.aws_eks_cluster.main
```

## Outputs

After applying, get output values:

```bash
# All outputs
terraform output

# Specific output
terraform output eks_cluster_name

# JSON format
terraform output -json > outputs.json
```

**Important outputs:**
- `vpc_id` - VPC identifier
- `eks_cluster_name` - EKS cluster name for kubectl config
- `eks_cluster_endpoint` - EKS API endpoint
- `rds_endpoint` - Database connection string
- `ecr_repository_urls` - Docker image repository URLs
- `cloudfront_distribution_id` - For cache invalidation

## Security Best Practices

1. **Never commit state files** - Use remote backend
2. **Enable state locking** - Prevents concurrent modifications
3. **Use separate AWS accounts** - Dev/prod isolation
4. **Enable CloudTrail** - Audit all infrastructure changes
5. **Use Secrets Manager** - Don't hardcode credentials
6. **Enable encryption** - S3, EBS, RDS encryption
7. **Least privilege IAM** - Minimal permissions
8. **Network isolation** - Private subnets for data tier
9. **Review plans carefully** - Before applying
10. **Tag all resources** - For cost tracking and governance

## 보안 로그 중앙화 (Security Log Centralization)

모든 보안 관련 로그를 단일 S3 중앙 로그 버킷(`gympt-prod-logs-<account_id>`)에 통합 적재합니다.

| 로그 소스 | S3 prefix | 수집 방식 |
|---|---|---|
| CloudTrail (전 리전, 무결성 검증) | `cloudtrail/` | 직접 |
| VPC Flow Logs (ALL) | `vpc-flow-logs/` | 직접 |
| ALB Access Logs | `alb-access-logs/` | ALB 속성 (gitops ingress annotation) |
| CloudFront Access Logs | `cloudfront-logs/` | CloudWatch Logs vended delivery (V2) |
| WAF Logs | `waf-logs/cloudfront/` (CloudFront), `waf-logs/alb/` (ALB) | Kinesis Firehose |
| S3 Server Access Logs | `s3-access-logs/<bucket>/` | 직접 |
| Inspector Findings (HIGH/CRITICAL) | `inspector-findings/` | EventBridge → Kinesis Firehose |

- **Lifecycle**: 90일 후 Glacier 전환, 365일 후 만료 (`modules/s3`)
- **알림**: CloudWatch Alarm 및 Inspector findings → SNS → AWS Chatbot → Slack(`aws-resource-alert`) (`modules/cloudwatch`, `modules/inspector`)
- **무결성**: CloudTrail log file validation 활성화
- 버킷 정책(`modules/s3`)에서 각 로그 소스 서비스 주체(cloudtrail / delivery.logs / ELB 계정 / logging.s3 / firehose)에 해당 prefix 쓰기 권한을 부여

> 참고: Inspector 스캔은 구축 단계에서 finding 폭증으로 일시 비활성화될 수 있습니다. 파이프라인(EventBridge → Firehose → S3)은 유지되며 재활성화 시 자동으로 적재가 재개됩니다.

## Athena / Glue 로그 분석

`modules/glue`는 중앙 로그 버킷의 주요 로그 prefix를 Athena에서 바로 조회할 수 있도록 명시적인 Glue Catalog Table로 관리합니다. 팀원이 각자 `terraform import`로 기존 Glue table을 state에 편입하지 않고, Terraform 코드에서 table을 생성해 state 충돌을 피합니다.

| Glue table | S3 prefix | 용도 |
|---|---|---|
| `alb_access_logs` | `alb-access-logs/` | ALB 요청, 상태 코드, latency, user agent 분석 |
| `cloudfront_access_logs` | `cloudfront-logs/` | CloudFront edge 요청, cache/result type, URI 분석 |
| `cloudtrail_logs` | `cloudtrail/AWSLogs/<account_id>/CloudTrail/` | AWS API 감사 로그 분석 |
| `inspector_findings` | `inspector-findings/<year>/<month>/<day>/<hour>/` | Inspector HIGH/CRITICAL finding 분석. Partition projection 사용 |
| `s3_access_logs` | `s3-access-logs/` | S3 server access log 분석 |
| `vpc_flow_logs` | `vpc-flow-logs/AWSLogs/<account_id>/vpcflowlogs/<region>/` | VPC 네트워크 흐름 분석 |
| `waf_alb_logs` | `waf-logs/alb/<year>/<month>/<day>/<hour>/` | ALB WAF 요청/action/rule 분석. Partition projection 사용 |
| `waf_cloudfront_logs` | `waf-logs/cloudfront/<year>/<month>/<day>/<hour>/` | CloudFront WAF 요청/action/rule 분석. Partition projection 사용 |

`AWSLogs/` prefix는 별도 CloudTrail 계열 경로로 남겨 두며, 이 Glue module은 `cloudtrail/` prefix의 CloudTrail table만 관리합니다.

Athena workgroup은 `modules/athena`에서 생성하며, 쿼리 결과는 `gympt-<env>-athena-results-<account_id>/athena-results/`에 저장됩니다.

Grafana는 `grafana-athena-datasource` plugin으로 Athena를 조회합니다. Prod 환경은 `aws_iam_role.grafana_athena` IRSA role을 `monitoring/kube-prometheus-stack-grafana` service account에 연결해 Athena, Glue, logs bucket, Athena results bucket 접근 권한을 부여합니다.

검증 쿼리:

```sql
SELECT * FROM alb_access_logs LIMIT 10;
SELECT date, time, client_ip, uri_stem, status FROM cloudfront_access_logs LIMIT 10;
SELECT eventtime, eventsource, eventname FROM cloudtrail_logs LIMIT 10;
SELECT detail.severity, detail.title FROM inspector_findings WHERE year='2026' AND month='06' AND day='05' AND hour='17' LIMIT 10;
SELECT bucket, operation, key, http_status FROM s3_access_logs LIMIT 10;
SELECT srcaddr, dstaddr, action FROM vpc_flow_logs LIMIT 10;
SELECT action, httprequest.clientip, httprequest.uri FROM waf_alb_logs WHERE year='2026' AND month='06' AND day='08' AND hour='00' LIMIT 10;
SELECT action, httprequest.clientip, httprequest.uri FROM waf_cloudfront_logs WHERE year='2026' AND month='06' AND day='08' AND hour='00' LIMIT 10;
```

## 재해 복구 (Disaster Recovery)

### 목표

- **RTO (Recovery Time Objective): 30분** — 장애 발생부터 서비스 정상화까지의 목표 시간
- **RPO (Recovery Point Objective): 5분** — 허용 가능한 최대 데이터 손실 시간

### 컴포넌트별 복구 능력

| 컴포넌트 | RTO | RPO | 메커니즘 |
|---|---|---|---|
| RDS PostgreSQL | ~1–2분 (자동 failover) | ~0 (동기 복제) / 5분 (PITR) | Multi-AZ, PITR, 30일 자동 백업 |
| DynamoDB | 복구 수분 | 5분 | PITR (연속 백업) |
| ElastiCache Redis | ~1–2분 (failover) | 스냅샷 시점 | Multi-AZ, 7일 스냅샷 |
| EKS 워크로드 | 수분 (자동 재스케줄) | — (무상태) | Karpenter + HPA 자동 복구 |
| S3 | 즉시 | 버전 단위 | 11 9's 내구성, Versioning |

### 근거

- **RPO 5분**: DynamoDB PITR과 RDS PITR이 5분 단위 복구를 보장한다. Multi-AZ 동기 복제 덕분에 활성 인스턴스 장애 시 데이터 손실은 사실상 0이며, 시점 복구가 필요한 경우에도 최대 5분 이내로 제한된다.
- **RTO 30분**: 개별 컴포넌트는 자동 failover로 1–2분 내 복구되지만, 전체 서비스 복구·데이터 정합성 검증·수동 개입 여유를 포함한 현실적인 목표값이다.
- **무인 복구**: 노드/파드 장애는 Karpenter(노드)와 HPA(파드) 자동 스케일링으로 수분 내 무인 복구된다 (Phase 5 인프라 복구).

## 접근 제어 (Boundary 제로 트러스트)

Bastion 없이 내부 인프라에 접근하는 HashiCorp Boundary 게이트웨이. SSM은 EC2 부트스트랩용 일회성으로만 쓰고, 일반 인프라 접근은 Boundary로 일원화한다.

- **구성**: Controller + Worker를 EC2 1대에 combined로 운영 (별도 Bastion/Worker EC2 없음, SSM으로 관리 접속). 상태 DB는 RDS의 `boundary` DB, 봉인 키는 KMS CMK 3개(root/worker-auth/recovery).
- **Target**: RDS PostgreSQL(5432), ElastiCache Redis(6379), EKS API(443). 팀원은 각자 Boundary 클라이언트로 로그인 후 `boundary connect`로 터널 접속하며 모든 세션이 감사 기록된다.
- **SG 연동**: RDS/Redis 보안그룹이 Boundary SG를 인바운드 허용한다. 이 허용은 `data.aws_security_group.boundary`로 조회해 `allowed_security_group_ids`에 포함시켜 **Terraform으로 영구 관리**한다(수동 추가 시 apply마다 사라지는 drift 방지).
- **비용**: 평소 Controller EC2를 중지해 비용을 절감한다(EIP 미할당 시 재시작마다 public IP 변경).

## Cost Optimization

### Development

```hcl
# Use smaller instance types
node_instance_types = ["t3.small"]

# Disable multi-AZ
multi_az = false

# Reduce backup retention
backup_retention = 7

# Use spot instances for non-critical workloads
spot_instance_pools = 2
```

### Production

```hcl
# Use savings plans or reserved instances
# Enable multi-AZ for high availability
# Use appropriate instance sizes
# Enable S3 lifecycle policies
# Use CloudFront for CDN
```

## Troubleshooting

### Error: "Error locking state"

Someone else is running terraform or lock wasn't released.

```bash
# Force unlock (use with caution)
terraform force-unlock LOCK_ID
```

### Error: "Provider configuration not present"

```bash
terraform init
```

### Error: "cycle in resource dependencies"

Review resource dependencies, likely circular reference.

### State drift detected

```bash
# Refresh state
terraform refresh

# Re-import resource if needed
terraform import <resource> <id>
```

### Plan shows unexpected changes

```bash
# Compare with actual AWS resources
terraform plan -refresh-only

# Check what changed in state
git diff terraform.tfstate
```

## CI/CD Integration

Integrated with GitHub Actions:

```yaml
# .github/workflows/terraform-plan.yml
terraform init
terraform plan -out=tfplan
```

See `GITHUB-ACTIONS.md` for complete setup.

## Additional Resources

- [Terraform Documentation](https://www.terraform.io/docs)
- [AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Terraform Best Practices](https://www.terraform-best-practices.com/)

## Support

- **Infrastructure Issues:** Create issue in `gympt-infra` repository
- **AWS Account Access:** Contact platform team
- **Cost Questions:** Review AWS Cost Explorer

---

**Last Updated:** 2026-06-08
**Maintained by:** Platform Team
