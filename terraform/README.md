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
| WAF Logs | `waf-logs/` (CloudFront), `waf-logs/alb/` (ALB) | Kinesis Firehose |
| S3 Server Access Logs | `s3-access-logs/<bucket>/` | 직접 |
| Inspector Findings (HIGH/CRITICAL) | `inspector-findings/` | EventBridge → Kinesis Firehose |

- **Lifecycle**: 90일 후 Glacier 전환, 365일 후 만료 (`modules/s3`)
- **알림**: CloudWatch Alarm 및 Inspector findings → SNS → AWS Chatbot → Slack(`aws-resource-alert`) (`modules/cloudwatch`, `modules/inspector`)
- **무결성**: CloudTrail log file validation 활성화
- 버킷 정책(`modules/s3`)에서 각 로그 소스 서비스 주체(cloudtrail / delivery.logs / ELB 계정 / logging.s3 / firehose)에 해당 prefix 쓰기 권한을 부여

> 참고: Inspector 스캔은 구축 단계에서 finding 폭증으로 일시 비활성화될 수 있습니다. 파이프라인(EventBridge → Firehose → S3)은 유지되며 재활성화 시 자동으로 적재가 재개됩니다.

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

**Last Updated:** 2024-05-19  
**Maintained by:** Platform Team
