# GYMPT Infrastructure Scripts

Automation scripts for managing GYMPT infrastructure deployment, operations, and maintenance.

---

## Prod 환경 전체 배포 순서

> 처음 구축하거나 전체 재배포할 때의 단계별 실행 순서입니다.
> 각 단계 완료 확인 후 다음으로 넘어가세요.

### 사전 준비

```bash
# 필수 도구 설치 확인
aws --version          # AWS CLI v2 이상
terraform -version     # 1.7.0 이상
kubectl version        # 1.30 이상
helm version           # 3.x
argocd version         # 2.x (선택)

# AWS 자격증명 설정
aws configure
aws sts get-caller-identity  # 확인

# prod 배포에 필요한 시크릿 환경변수 설정
export TF_VAR_rds_master_password="<RDS 마스터 패스워드>"
export TF_VAR_redis_auth_token="<Redis 인증 토큰>"
export TF_VAR_boundary_db_password="<Boundary DB 패스워드>"
export TF_VAR_alarm_email="<알림 이메일>"
```

---

### STEP 1 — Terraform 백엔드 초기화

```bash
cd gympt-infra
./scripts/init-backend.sh
```
S3 state 버킷과 DynamoDB lock 테이블을 생성합니다.

---

### STEP 2 — Terraform 초기화

```bash
cd terraform/environments/prod

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

terraform init \
  -backend-config="bucket=gympt-tfstate-${ACCOUNT_ID}" \
  -backend-config="key=prod/terraform.tfstate" \
  -backend-config="region=ap-northeast-2" \
  -backend-config="dynamodb_table=gympt-tfstate-lock"
```

---

### STEP 3 — 인프라 단계적 Apply

순서가 중요합니다. 의존관계 때문에 반드시 아래 순서로 실행하세요.

```bash
# 3-1. 네트워크 (VPC, 서브넷, NAT, 엔드포인트)
terraform apply -target=module.vpc

# 3-2. ECR 레포지토리 (이미지 push 전에 필요)
terraform apply -target=module.ecr

# 3-3. EKS 클러스터 (15~20분 소요)
terraform apply -target=module.eks

# 3-4. 데이터 계층 (RDS, DynamoDB, ElastiCache)
terraform apply \
  -target=module.rds \
  -target=module.dynamodb \
  -target=module.elasticache

# 3-5. 스토리지 및 메시징
terraform apply \
  -target=module.s3 \
  -target=module.sqs \
  -target=module.eventbridge

# 3-6. IAM, Karpenter, GitHub OIDC
terraform apply \
  -target=module.iam \
  -target=module.karpenter \
  -target=module.github_oidc

# 3-7. 나머지 전체 (Lambda, CloudWatch, CloudTrail, KVS, Boundary 등)
terraform plan -out=tfplan
terraform apply tfplan
```

---

### STEP 4 — kubeconfig 설정

```bash
cd gympt-infra
./scripts/get-kubeconfig.sh prod

# 연결 확인
kubectl get nodes
```

---

### STEP 5 — 인프라 상태 확인

```bash
./scripts/utilities/check-resources.sh prod
```

EKS, RDS, Redis, S3, SQS 등 전체 상태를 출력합니다.

---

> **다음 단계**: `gympt-gitops/scripts/README.md` — 플랫폼 설치 및 앱 배포

## Directory Structure

```
scripts/
├── init-backend.sh           # Initialize Terraform backend
├── deploy-infra-dev.sh       # Deploy dev infrastructure
├── get-kubeconfig.sh         # Get EKS cluster credentials
├── backup-state.sh           # Backup/restore Terraform state
├── validate-all.sh           # Validate all Terraform configs
├── plan-all.sh               # Plan all environments
├── apply-all.sh              # Apply all environments
├── destroy-all.sh            # Destroy infrastructure
├── db-tunnel.sh              # Create DB tunnel via SSM
└── utilities/
    ├── check-resources.sh    # Check AWS resource status
    └── rotate-credentials.sh # Rotate DB/Redis credentials
```

## Prerequisites

### Required Tools

- **AWS CLI v2**: AWS command-line interface
- **Terraform >= 1.5**: Infrastructure as code
- **kubectl**: Kubernetes CLI (for cluster operations)
- **jq**: JSON processor (for parsing outputs)
- **Session Manager Plugin**: For SSM tunneling

### Installation

```bash
# AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Terraform
wget https://releases.hashicorp.com/terraform/1.6.6/terraform_1.6.6_linux_amd64.zip
unzip terraform_1.6.6_linux_amd64.zip
sudo mv terraform /usr/local/bin/

# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# jq
sudo apt-get install jq  # Ubuntu/Debian
sudo yum install jq      # Amazon Linux/RHEL

# Session Manager Plugin
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o "session-manager-plugin.deb"
sudo dpkg -i session-manager-plugin.deb
```

### AWS Configuration

```bash
# Configure AWS credentials
aws configure

# Set default region
export AWS_REGION=ap-northeast-2
```

### Make Scripts Executable

```bash
cd /path/to/gympt-infra/scripts
chmod +x *.sh utilities/*.sh
```

## Core Scripts

### 1. init-backend.sh

Initialize Terraform S3 backend and DynamoDB state locking.

```bash
# Initialize backend
./scripts/init-backend.sh

# With custom region
AWS_REGION=us-west-2 ./scripts/init-backend.sh
```

**What it does:**
- Creates S3 bucket for state storage
- Enables versioning and encryption
- Creates DynamoDB table for state locking
- Configures security policies

### 2. deploy-infra-dev.sh

Deploy development infrastructure.

```bash
# Interactive deployment
./scripts/deploy-infra-dev.sh

# Auto-approve (CI/CD)
./scripts/deploy-infra-dev.sh --yes

# Plan only (no apply)
./scripts/deploy-infra-dev.sh --plan-only

# Destroy infrastructure
./scripts/deploy-infra-dev.sh --destroy
```

**What it does:**
- Initializes Terraform backend
- Validates configuration
- Creates execution plan
- Applies infrastructure changes
- Outputs deployment results

### 3. get-kubeconfig.sh

Configure kubectl access to EKS cluster.

```bash
# Get dev kubeconfig
./scripts/get-kubeconfig.sh

# Get prod kubeconfig
./scripts/get-kubeconfig.sh prod

# Test cluster connectivity
./scripts/get-kubeconfig.sh dev
kubectl get nodes
```

**What it does:**
- Updates local kubeconfig
- Tests cluster connectivity
- Displays cluster information
- Shows system pods status

### 4. backup-state.sh

Backup and restore Terraform state files.

```bash
# Backup all environments
./scripts/backup-state.sh

# Backup specific environment
./scripts/backup-state.sh --env dev

# List existing backups
./scripts/backup-state.sh --list

# Restore from latest backup
./scripts/backup-state.sh --restore dev
```

**What it does:**
- Creates timestamped state backups
- Stores in separate S3 bucket
- Enables point-in-time recovery
- Automatic 90-day lifecycle

### 5. validate-all.sh

Validate all Terraform modules and environments.

```bash
# Validate everything
./scripts/validate-all.sh
```

**What it does:**
- Checks Terraform formatting
- Validates all modules
- Validates all environments
- Reports errors and warnings

### 6. plan-all.sh

Run terraform plan for all environments.

```bash
# Plan all environments
./scripts/plan-all.sh

# Plan specific environment
./scripts/plan-all.sh --env dev

# Plan destroy
./scripts/plan-all.sh --destroy
```

**What it does:**
- Plans changes for all environments
- Saves plan files
- Reports planned changes
- No destructive operations

### 7. apply-all.sh

Apply infrastructure changes to all environments.

```bash
# Apply all environments (interactive)
./scripts/apply-all.sh

# Apply with auto-approve
./scripts/apply-all.sh --yes

# Apply specific environment
./scripts/apply-all.sh --env prod
```

**What it does:**
- Applies changes to multiple environments
- Requires explicit confirmation for prod
- Saves outputs to JSON
- Reports success/failure

**WARNING:** Production deployments require typing "APPLY PRODUCTION" to confirm.

### 8. destroy-all.sh

Destroy infrastructure (USE WITH EXTREME CAUTION).

```bash
# Destroy specific environment
./scripts/destroy-all.sh --env dev

# Destroy all (requires multiple confirmations)
./scripts/destroy-all.sh
```

**What it does:**
- Destroys all AWS resources
- Creates automatic backup first
- Requires multiple confirmations
- 10-second countdown before execution

**DANGER:** This permanently deletes all resources including data!

### 9. db-tunnel.sh

Create SSM tunnel to RDS database.

```bash
# Connect to dev database
./scripts/db-tunnel.sh

# Connect to prod database
./scripts/db-tunnel.sh prod

# Use custom local port
./scripts/db-tunnel.sh dev 15432

# Then connect with psql
psql -h localhost -p 5432 -U gympt_admin -d gympt
```

**What it does:**
- Creates secure SSM tunnel via EKS node
- No need for bastion host
- Retrieves credentials from Secrets Manager
- Supports custom local ports

## Utility Scripts

### check-resources.sh

Check status of all GYMPT AWS resources.

```bash
# Check dev resources
./scripts/utilities/check-resources.sh

# Check prod resources
./scripts/utilities/check-resources.sh prod
```

**Reports:**
- VPC and networking status
- EKS cluster health
- RDS database status
- ElastiCache status
- DynamoDB tables
- S3 buckets and sizes
- ECR repositories and images
- SQS queues and messages
- KVS streams
- Lambda functions
- CloudFront distributions
- Estimated monthly costs

### rotate-credentials.sh

Rotate database and Redis credentials.

```bash
# Rotate all credentials
./scripts/utilities/rotate-credentials.sh dev

# Rotate only RDS
./scripts/utilities/rotate-credentials.sh dev --rds-only

# Rotate only Redis
./scripts/utilities/rotate-credentials.sh dev --redis-only

# Rotate without restarting apps
./scripts/utilities/rotate-credentials.sh dev --no-restart
```

**What it does:**
- Generates secure random passwords
- Backs up current credentials
- Updates RDS master password
- Updates Redis auth token
- Updates Secrets Manager
- Updates Kubernetes secrets
- Restarts affected pods
- Waits for rollout completion

**Best Practice:** Rotate credentials every 90 days.

## Common Workflows

### Initial Infrastructure Setup

```bash
# 1. Initialize backend
./scripts/init-backend.sh

# 2. Validate configuration
./scripts/validate-all.sh

# 3. Deploy dev environment
./scripts/deploy-infra-dev.sh

# 4. Get kubeconfig
./scripts/get-kubeconfig.sh dev

# 5. Verify deployment
./scripts/utilities/check-resources.sh dev
```

### Production Deployment

```bash
# 1. Backup current state
./scripts/backup-state.sh --env prod

# 2. Plan changes
./scripts/plan-all.sh --env prod

# 3. Review plan carefully
cat prod-plan-*.tfplan

# 4. Apply changes
./scripts/apply-all.sh --env prod

# 5. Verify deployment
./scripts/utilities/check-resources.sh prod
kubectl get nodes
kubectl get pods -A
```

### Database Operations

```bash
# 1. Create tunnel
./scripts/db-tunnel.sh dev

# 2. In another terminal, connect
psql -h localhost -p 5432 -U gympt_admin -d gympt

# 3. Run queries
SELECT * FROM users LIMIT 10;

# 4. Disconnect (Ctrl+C in tunnel terminal)
```

### Credential Rotation

```bash
# 1. Backup state
./scripts/backup-state.sh --env prod

# 2. Rotate credentials
./scripts/utilities/rotate-credentials.sh prod

# 3. Verify connectivity
./scripts/db-tunnel.sh prod
psql -h localhost -p 5432 -U gympt_admin -d gympt -c "SELECT 1;"

# 4. Monitor applications
kubectl logs -f deployment/api-gateway -n default
```

### Disaster Recovery

```bash
# 1. List available backups
./scripts/backup-state.sh --list

# 2. Restore state
./scripts/backup-state.sh --restore dev

# 3. Verify state
cd terraform/environments/dev
terraform show

# 4. Re-apply if needed
./scripts/deploy-infra-dev.sh
```

### Environment Teardown

```bash
# 1. Backup state (just in case)
./scripts/backup-state.sh --env dev

# 2. Destroy infrastructure
./scripts/destroy-all.sh --env dev

# 3. Verify deletion
aws eks list-clusters --region ap-northeast-2
aws rds describe-db-instances --region ap-northeast-2
```

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Deploy Infrastructure

on:
  push:
    branches: [main]
    paths:
      - 'terraform/**'

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ap-northeast-2

      - name: Validate Terraform
        run: ./scripts/validate-all.sh

      - name: Plan Infrastructure
        run: ./scripts/plan-all.sh --env dev

      - name: Apply Infrastructure
        run: ./scripts/apply-all.sh --env dev --yes
        if: github.ref == 'refs/heads/main'
```

## Environment Variables

```bash
# AWS Configuration
export AWS_REGION=ap-northeast-2
export AWS_PROFILE=gympt-prod

# Terraform Configuration
export TF_VAR_environment=prod
export TF_VAR_region=ap-northeast-2

# Script Behavior
export TF_IN_AUTOMATION=1  # Disable interactive prompts
```

## Troubleshooting

### Common Issues

**1. Backend initialization fails**
```bash
# Check AWS credentials
aws sts get-caller-identity

# Check bucket permissions
aws s3 ls s3://gympt-tfstate-<account-id>

# Re-initialize
./scripts/init-backend.sh
```

**2. State lock errors**
```bash
# List locks
aws dynamodb scan --table-name gympt-tfstate-lock

# Force unlock (use with caution)
cd terraform/environments/dev
terraform force-unlock <lock-id>
```

**3. Kubeconfig not working**
```bash
# Verify cluster exists
aws eks describe-cluster --name gympt-dev-cluster

# Re-get kubeconfig
./scripts/get-kubeconfig.sh dev

# Test connection
kubectl cluster-info
```

**4. DB tunnel fails**
```bash
# Check EKS nodes
aws ec2 describe-instances \
  --filters "Name=tag:eks:cluster-name,Values=gympt-dev-cluster"

# Check RDS status
aws rds describe-db-instances --db-instance-identifier gympt-dev-postgres

# Check Session Manager plugin
session-manager-plugin --version
```

**5. Credential rotation issues**
```bash
# Check Secrets Manager
aws secretsmanager list-secrets | grep gympt

# Restore backup
aws secretsmanager get-secret-value --secret-id gympt-dev-db-credentials-backup-<timestamp>

# Manual RDS password reset
aws rds modify-db-instance \
  --db-instance-identifier gympt-dev-postgres \
  --master-user-password '<new-password>' \
  --apply-immediately
```

## Security Best Practices

1. **Never commit credentials**: Use AWS Secrets Manager and IAM roles
2. **Use MFA**: Enable MFA for AWS console and CLI operations
3. **Least privilege**: Grant minimum required IAM permissions
4. **Rotate regularly**: Rotate credentials every 90 days
5. **Audit logs**: Enable CloudTrail and review regularly
6. **Backup state**: Always backup before destructive operations
7. **Separate environments**: Use different AWS accounts for prod/dev
8. **Review plans**: Always review terraform plans before applying

## Performance Tips

1. **Parallel operations**: Use `-parallelism` flag for faster applies
2. **Targeted updates**: Use `-target` to update specific resources
3. **State refresh**: Disable with `-refresh=false` for faster plans
4. **Local backend**: Use local backend for dev/testing

## Support

For issues or questions:
- Check logs in `/tmp/tf-*.log`
- Review AWS CloudWatch Logs
- Check Terraform state: `terraform show`
- Review this README and inline help: `script.sh --help`

## Contributing

When adding new scripts:
1. Follow existing naming conventions
2. Add error handling (`set -euo pipefail`)
3. Include usage information (`--help` flag)
4. Add colorized output for readability
5. Document in this README
6. Test in dev before prod
7. Make executable (`chmod +x`)

## License

Copyright 2026 GYMPT. All rights reserved.
