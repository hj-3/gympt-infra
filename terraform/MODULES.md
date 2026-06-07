# Terraform Modules - Complete Implementation

## Overview

Complete Terraform infrastructure implementation for GymPT platform with 20 modules covering all AWS services.

## Module Structure

All modules follow the standard structure:
```
module-name/
├── main.tf       # Resource definitions
├── variables.tf  # Input variables
└── outputs.tf    # Output values
```

## Implemented Modules

### 1. VPC Module (`modules/vpc/`)

**Purpose:** Multi-AZ VPC with public, private-app, and private-db subnets

**Resources:**
- VPC with DNS support
- 2 public subnets
- 2 private-app subnets (for EKS)
- 2 private-db subnets (for RDS/ElastiCache)
- Internet Gateway
- 2 NAT Gateways (one per AZ)
- Route tables for each subnet type
- VPC Endpoints (S3, ECR API, ECR DKR)
- Security group for VPC endpoints

**Outputs:** VPC ID, subnet IDs, security group IDs

### 2. EKS Module (`modules/eks/`)

**Purpose:** Kubernetes cluster with managed node groups

**Resources:**
- EKS cluster (v1.28)
- OIDC provider for IRSA
- General-purpose managed node group
- Optional GPU node group (g4dn instances)
- Cluster and node IAM roles
- Security groups for cluster and nodes
- EKS addons: vpc-cni, coredns, kube-proxy, ebs-csi-driver
- EBS CSI driver IAM role

**Outputs:** Cluster name, endpoint, OIDC provider, security groups

### 3. ECR Module (`modules/ecr/`)

**Purpose:** Docker image repositories

**Resources:**
- 5 ECR repositories:
  - backend-api
  - agent-service
  - posture-analysis-service
  - report-service
  - remediation-worker
- Image scanning on push
- Lifecycle policies (keep last 10 images)

**Outputs:** Repository URLs and ARNs

### 4. RDS Module (`modules/rds/`)

**Purpose:** PostgreSQL database

**Resources:**
- RDS PostgreSQL 15.4
- DB subnet group
- Security group
- Parameter group with logging enabled
- CloudWatch alarms (CPU, storage, memory)

**Configuration:**
- Dev: db.t3.micro, single-AZ, 7-day backups
- Prod: db.t3.large, multi-AZ, 30-day backups

**Outputs:** Endpoint, address, port, security group

### 5. DynamoDB Module (`modules/dynamodb/`)

**Purpose:** NoSQL tables for high-throughput data

**Resources:**
- 4 tables with GSIs:
  - workout_sessions (userId, sessionId)
  - posture_events (userId, eventId)
  - wearable_events (userId, timestamp)
  - agent_interactions (sessionId, timestamp)
- Point-in-time recovery enabled
- Server-side encryption

**Outputs:** Table names and ARNs

### 6. ElastiCache Module (`modules/elasticache/`)

**Purpose:** Redis caching layer

**Resources:**
- Redis 7.0 replication group
- Cache subnet group
- Security group
- Parameter group (LRU eviction)
- CloudWatch alarms (CPU, memory, evictions, connections)

**Configuration:**
- Dev: cache.t3.micro, 1 node, no auth
- Prod: cache.t3.medium, 2 nodes, auth token, multi-AZ

**Outputs:** Primary and reader endpoints

### 7. S3 Module (`modules/s3/`)

**Purpose:** Object storage buckets

**Resources:**
- 5 S3 buckets:
  - frontend (with CloudFront OAI)
  - media (user uploads)
  - logs (application and access logs)
  - lambda-artifacts (deployment packages)
  - athena-results (query results)
- Versioning enabled on frontend and media
- Lifecycle policies
- Server-side encryption (AES256)
- Public access blocked
- Account ID suffix for global uniqueness

**Outputs:** Bucket IDs, ARNs, domain names

### 8. CloudFront Module (`modules/cloudfront/`)

**Purpose:** CDN for frontend distribution

**Resources:**
- CloudFront distribution
- Origin Access Identity for S3
- SPA routing CloudFront Function
- Custom error responses (403/404 → index.html)
- Cache behaviors:
  - Default: frontend assets
  - /api/*: API passthrough (no cache)
  - /static/*: long TTL
- S3 bucket policy for OAI

**Configuration:**
- Dev: PriceClass_100 (North America + Europe)
- Prod: PriceClass_200 (global except Oceania)

**Outputs:** Distribution ID, domain name, OAI ARN

### 9. Lambda Module (`modules/lambda/`)

**Purpose:** 8 serverless functions

**Resources:**
- 8 Lambda functions:
  - agent-action (512MB, 30s)
  - report-generator (1024MB, 300s)
  - posture-event-processor (512MB, 60s)
  - thumbnail-generator (1024MB, 60s)
  - wearable-sync (512MB, 60s)
  - recommendation-update (512MB, 60s)
  - notification (256MB, 30s)
  - export (1024MB, 300s)
- Shared IAM execution role
- Custom policy (DynamoDB, S3, SQS, Bedrock, KMS Decrypt access)
- KMS CMK + alias (environment variable encryption, key rotation enabled)
- SQS event source mappings
- CloudWatch log groups
- CloudWatch alarms (errors, duration)
- Optional VPC configuration
- X-Ray tracing

**Outputs:** Function ARNs, names, log groups

### 10. SQS Module (`modules/sqs/`)

**Purpose:** Message queues for async processing

**Resources:**
- 7 FIFO queues with DLQs:
  - report-generation
  - posture-event
  - thumbnail-generation
  - wearable-sync
  - recommendation-update
  - notification
  - export
- Message retention: 7 days
- Visibility timeout: 6x function timeout
- CloudWatch alarms for each queue

**Outputs:** Queue URLs, ARNs, DLQ ARNs

### 11. EventBridge Module (`modules/eventbridge/`)

**Purpose:** Event-driven architecture

**Resources:**
- Custom event bus
- Event rules:
  - workout_completed
  - posture_analyzed
  - daily_report_schedule (cron: 1 AM UTC)
- Event targets (SQS queues, Lambda functions)
- Lambda permissions for EventBridge
- Event archive (30/90 days retention)

**Outputs:** Event bus ARN, archive ARN

### 12. WAF Module (`modules/waf/`)

**Purpose:** Web application firewall

**Resources:**
- WAFv2 Web ACL
- Rate limiting rule (2000/5000 requests per 5 min)
- AWS managed rule sets:
  - Common Rule Set
  - Known Bad Inputs
  - SQL Injection
- CloudWatch logging

**Outputs:** Web ACL ID and ARN

### 13. Bedrock Module (`modules/bedrock/`)

**Purpose:** IAM roles for AWS Bedrock

**Resources:**
- Bedrock service IAM role
- S3 access policy
- CloudWatch Logs permissions

**Outputs:** Role ARN

### 14. IAM Module (`modules/iam/`)

**Purpose:** IRSA roles for EKS pods

**Resources:**
- Pod-level IAM roles (per service account)
- S3 access policy
- DynamoDB access policy
- Trust policy with OIDC provider

**Service Accounts:**
- backend-api
- agent-service
- posture-analysis-service
- report-service

**Outputs:** Pod role ARNs

### 15. Karpenter Module (`modules/karpenter/`)

**Purpose:** Kubernetes node autoscaling

**Resources:**
- Karpenter controller IAM role (IRSA)
- Controller policy (EC2, pricing, EKS access)
- Node instance profile

**Outputs:** Controller role ARN, instance profile name

### 16. CloudWatch Module (`modules/cloudwatch/`)

**Purpose:** Monitoring and alerting

**Resources:**
- SNS topic for alarms
- Email subscription (optional)
- CloudWatch dashboard (EKS, RDS metrics)
- Application log group
- AWS Chatbot Slack channel configuration (alarms + Inspector alerts → `aws-resource-alert` 채널)

**Outputs:** SNS topic ARN, dashboard name

### 17. CloudTrail Module (`modules/cloudtrail/`)

**Purpose:** Audit logging

**Resources:**
- CloudTrail trail
- Multi-region enabled
- Log file validation
- S3 bucket for trail logs

**Outputs:** Trail ARN

### 18. Athena Module (`modules/athena/`)

**Purpose:** SQL queries on S3 data

**Resources:**
- Athena workgroup
- Database for logs
- S3 output location

**Outputs:** Workgroup name, database name

### 19. Glue Module (`modules/glue/`)

**Purpose:** Data catalog and ETL

**Resources:**
- Glue catalog database
- Crawler for logs bucket
- Glue catalog table: `alb_access_logs`
- Glue catalog table: `cloudtrail_logs`
- Glue catalog table: `vpc_flow_logs`
- IAM role for Glue
- S3 access policy

**Outputs:** Database name, crawler name, Glue role ARN, catalog table names

### 20. Monitoring Module (`modules/monitoring/`)

**Purpose:** Advanced CloudWatch alarms

**Resources:**
- EKS CPU/memory alarms
- SQS message age alarms (per queue)
- Monitoring dashboard (Lambda, SQS)

**Outputs:** Dashboard name

### 21. Inspector Module (`modules/inspector/`)

**Purpose:** Vulnerability findings alerting & archival

**Resources:**
- EventBridge rule (Inspector2 HIGH/CRITICAL findings)
- SNS topic (→ AWS Chatbot Slack)
- Kinesis Firehose delivery stream (findings → S3 `inspector-findings/`)
- IAM roles (Firehose S3 write, EventBridge → Firehose)

**Outputs:** SNS topic ARN

## Environment Configurations

### Development (`environments/dev/`)

**Files:**
- `main.tf` - Module orchestration
- `outputs.tf` - Environment outputs
- `terraform.tfvars` - Variable values

**Configuration:**
- VPC: 10.0.0.0/16
- EKS: 2-10 t3.large nodes, 0-3 GPU nodes
- RDS: db.t3.micro, single-AZ, 7-day backups
- Redis: cache.t3.micro, 1 node
- Lambda: No VPC, no X-Ray
- Log retention: 7 days

**Cost optimization:**
- Small instance types
- No multi-AZ
- Short backup retention
- Deletion protection disabled

### Production (`environments/prod/`)

**Files:**
- `main.tf` - Module orchestration
- `variables.tf` - Sensitive variables
- `outputs.tf` - Environment outputs
- `terraform.tfvars` - Variable values

**Configuration:**
- VPC: 10.1.0.0/16
- EKS: 3-20 t3.xlarge nodes, 1-5 GPU nodes
- RDS: db.t3.large, multi-AZ, 30-day backups
- Redis: cache.t3.medium, 2 nodes, auth enabled
- Lambda: VPC enabled, X-Ray enabled
- Log retention: 30 days
- Deletion protection enabled

**Security:**
- Immutable ECR images
- Auth tokens for Redis
- Secrets via variables (terraform.tfvars.secret)
- Multi-AZ for high availability

## Usage

### Initialize Environment

```bash
cd terraform/environments/dev

terraform init \
  -backend-config="bucket=gympt-terraform-state" \
  -backend-config="key=dev/terraform.tfstate" \
  -backend-config="region=ap-northeast-2" \
  -backend-config="dynamodb_table=gympt-terraform-locks"
```

### Plan Changes

```bash
terraform plan
```

### Apply Infrastructure

```bash
terraform apply
```

### Get Outputs

```bash
terraform output
terraform output -json > outputs.json
```

## Key Features

1. **Modular Design:** Reusable modules with clear interfaces
2. **Multi-Environment:** Separate dev/prod with different configs
3. **High Availability:** Multi-AZ for critical resources (prod)
4. **Security:** Encryption at rest, VPC isolation, least privilege IAM
5. **Cost Optimization:** Environment-specific sizing
6. **Monitoring:** CloudWatch alarms and dashboards
7. **Compliance:** CloudTrail, VPC Flow Logs (via S3)
8. **Disaster Recovery:** Automated backups, versioning

## Dependencies Graph

```
vpc → eks → (iam, karpenter)
vpc → (rds, elasticache)
vpc → lambda (optional VPC)
s3 → cloudfront
s3 → (lambda, athena, glue, cloudtrail)
sqs → (lambda event sources, eventbridge targets)
eks → (rds, elasticache) security groups
eks OIDC → (iam, karpenter)
cloudwatch → (monitoring, alarms)
```

## Total Resources Count

- **Dev:** ~150 resources
- **Prod:** ~180 resources

## Terraform State

- **Backend:** S3 with DynamoDB locking
- **Encryption:** AES256
- **Versioning:** Enabled
- **Separate state per environment:** dev/, prod/

---

**Last Updated:** 2026-06-08  
**Terraform Version:** >= 1.7.0  
**AWS Provider:** ~> 5.0
