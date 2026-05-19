#!/bin/bash

# GYMPT Infrastructure Repository Checker
# Validates Terraform infrastructure and identifies missing components

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TOTAL=0
PASSED=0
FAILED=0
WARNINGS=0

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo -e "${BLUE}===================================================${NC}"
echo -e "${BLUE}GYMPT Infrastructure Repository Structure Check${NC}"
echo -e "${BLUE}===================================================${NC}"
echo ""

# Function to check if file/directory exists
check_exists() {
    local path="$1"
    local type="$2"  # "file" or "dir"
    local description="$3"
    local priority="$4"  # "critical", "important", "optional"

    TOTAL=$((TOTAL + 1))

    if [ "$type" = "file" ]; then
        if [ -f "${PROJECT_ROOT}/${path}" ]; then
            echo -e "${GREEN}✓${NC} ${description}"
            PASSED=$((PASSED + 1))
            return 0
        fi
    else
        if [ -d "${PROJECT_ROOT}/${path}" ]; then
            echo -e "${GREEN}✓${NC} ${description}"
            PASSED=$((PASSED + 1))
            return 0
        fi
    fi

    if [ "$priority" = "critical" ]; then
        echo -e "${RED}✗${NC} ${description} (CRITICAL)"
        FAILED=$((FAILED + 1))
    elif [ "$priority" = "important" ]; then
        echo -e "${YELLOW}⚠${NC} ${description} (Missing)"
        WARNINGS=$((WARNINGS + 1))
    else
        echo -e "${YELLOW}○${NC} ${description} (Optional)"
        WARNINGS=$((WARNINGS + 1))
    fi
    return 1
}

# Repository Structure
echo -e "\n${BLUE}=== Repository Structure ===${NC}"
check_exists ".gitignore" "file" "Root .gitignore" "critical"
check_exists "README.md" "file" "Root README.md" "critical"
check_exists "CHECKLIST.md" "file" "Project checklist" "important"
check_exists "terraform" "dir" "Terraform directory" "critical"

# Core Infrastructure Modules
echo -e "\n${BLUE}=== Core Infrastructure Modules ===${NC}"
check_exists "terraform/modules/vpc/main.tf" "file" "VPC module" "critical"
check_exists "terraform/modules/eks/main.tf" "file" "EKS module" "critical"
check_exists "terraform/modules/rds/main.tf" "file" "RDS module" "critical"
check_exists "terraform/modules/dynamodb/main.tf" "file" "DynamoDB module" "critical"
check_exists "terraform/modules/elasticache/main.tf" "file" "ElastiCache module" "critical"
check_exists "terraform/modules/s3/main.tf" "file" "S3 module" "critical"
check_exists "terraform/modules/ecr/main.tf" "file" "ECR module" "critical"

# AWS Services Modules
echo -e "\n${BLUE}=== AWS Services Modules ===${NC}"
check_exists "terraform/modules/sqs/main.tf" "file" "SQS module" "critical"
check_exists "terraform/modules/eventbridge/main.tf" "file" "EventBridge module" "critical"
check_exists "terraform/modules/lambda/main.tf" "file" "Lambda module" "critical"
check_exists "terraform/modules/cloudfront/main.tf" "file" "CloudFront module" "critical"
check_exists "terraform/modules/waf/main.tf" "file" "WAF module" "critical"
check_exists "terraform/modules/kvs/main.tf" "file" "Kinesis Video Streams module" "important"

# Observability Modules
echo -e "\n${BLUE}=== Observability Modules ===${NC}"
check_exists "terraform/modules/cloudwatch/main.tf" "file" "CloudWatch module" "critical"
check_exists "terraform/modules/athena/main.tf" "file" "Athena module" "critical"
check_exists "terraform/modules/glue/main.tf" "file" "Glue module" "critical"
check_exists "terraform/modules/cloudtrail/main.tf" "file" "CloudTrail module" "critical"
check_exists "terraform/modules/monitoring/main.tf" "file" "Monitoring module" "important"

# Security & IAM Modules
echo -e "\n${BLUE}=== Security & IAM Modules ===${NC}"
check_exists "terraform/modules/iam/main.tf" "file" "IAM module" "critical"
check_exists "terraform/modules/bedrock/main.tf" "file" "Bedrock module" "important"

# Kubernetes Add-ons
echo -e "\n${BLUE}=== Kubernetes Add-ons ===${NC}"
check_exists "terraform/modules/karpenter/main.tf" "file" "Karpenter module" "critical"

# Environment Configurations
echo -e "\n${BLUE}=== Environment Configurations ===${NC}"
check_exists "terraform/environments/dev/main.tf" "file" "Dev environment main.tf" "critical"
check_exists "terraform/environments/dev/variables.tf" "file" "Dev environment variables.tf" "critical"
check_exists "terraform/environments/dev/outputs.tf" "file" "Dev environment outputs.tf" "critical"
check_exists "terraform/environments/prod/main.tf" "file" "Prod environment main.tf" "critical"
check_exists "terraform/environments/prod/variables.tf" "file" "Prod environment variables.tf" "critical"
check_exists "terraform/environments/prod/outputs.tf" "file" "Prod environment outputs.tf" "critical"

# CI/CD
echo -e "\n${BLUE}=== CI/CD Workflows ===${NC}"
check_exists ".github/workflows/terraform-plan-dev.yml" "file" "Dev plan workflow" "critical"
check_exists ".github/workflows/terraform-apply-dev.yml" "file" "Dev apply workflow" "critical"
check_exists ".github/workflows/terraform-plan-prod.yml" "file" "Prod plan workflow" "critical"
check_exists ".github/workflows/terraform-apply-prod.yml" "file" "Prod apply workflow" "critical"
check_exists ".github/workflows/terraform-validate.yml" "file" "Validation workflow" "optional"
check_exists ".github/workflows/terraform-drift-detection.yml" "file" "Drift detection workflow" "optional"

# Scripts
echo -e "\n${BLUE}=== Terraform Scripts ===${NC}"
check_exists "scripts/init-backend.sh" "file" "Initialize S3 backend" "important"
check_exists "scripts/plan-all.sh" "file" "Plan all environments" "important"
check_exists "scripts/apply-all.sh" "file" "Apply all environments" "important"
check_exists "scripts/validate-all.sh" "file" "Validate all modules" "important"
check_exists "scripts/fmt-all.sh" "file" "Format all Terraform files" "optional"

# Deployment Scripts
echo -e "\n${BLUE}=== Deployment Scripts ===${NC}"
check_exists "scripts/deploy-infra-dev.sh" "file" "Deploy dev infrastructure" "important"
check_exists "scripts/deploy-infra-prod.sh" "file" "Deploy prod infrastructure" "important"
check_exists "scripts/rollback-infra.sh" "file" "Rollback infrastructure" "optional"
check_exists "scripts/backup-state.sh" "file" "Backup Terraform state" "important"

# Utility Scripts
echo -e "\n${BLUE}=== Utility Scripts ===${NC}"
check_exists "scripts/get-kubeconfig.sh" "file" "Generate kubeconfig" "important"
check_exists "scripts/db-tunnel.sh" "file" "Create DB tunnel" "optional"
check_exists "scripts/rotate-credentials.sh" "file" "Rotate AWS credentials" "optional"

# Documentation
echo -e "\n${BLUE}=== Documentation ===${NC}"
check_exists "docs/architecture.md" "file" "Architecture diagrams" "important"
check_exists "docs/networking.md" "file" "Network architecture" "optional"
check_exists "docs/security.md" "file" "Security architecture" "important"
check_exists "docs/disaster-recovery.md" "file" "DR procedures" "important"
check_exists "docs/troubleshooting.md" "file" "Troubleshooting guide" "important"

# Testing
echo -e "\n${BLUE}=== Infrastructure Testing ===${NC}"
check_exists "terraform/tests" "dir" "Terratest directory" "optional"
check_exists ".github/workflows/security-scan.yml" "file" "Security scanning (tfsec, Checkov)" "important"

# Validate Terraform files
echo -e "\n${BLUE}=== Terraform Validation ===${NC}"
if command -v terraform &> /dev/null; then
    TOTAL=$((TOTAL + 1))
    if cd "${PROJECT_ROOT}/terraform/modules/vpc" && terraform validate &> /dev/null; then
        echo -e "${GREEN}✓${NC} Terraform syntax is valid"
        PASSED=$((PASSED + 1))
    else
        echo -e "${YELLOW}⚠${NC} Terraform validation failed (check syntax)"
        WARNINGS=$((WARNINGS + 1))
    fi
    cd "${PROJECT_ROOT}"
else
    echo -e "${YELLOW}○${NC} Terraform not installed (skipping validation)"
fi

# Summary
echo -e "\n${BLUE}====================================================${NC}"
echo -e "${BLUE}Summary${NC}"
echo -e "${BLUE}====================================================${NC}"
echo -e "Total checks:     ${TOTAL}"
echo -e "${GREEN}Passed:           ${PASSED}${NC}"
echo -e "${YELLOW}Warnings:         ${WARNINGS}${NC}"
echo -e "${RED}Failed (Critical): ${FAILED}${NC}"

PERCENTAGE=$((PASSED * 100 / TOTAL))
echo -e "\nCompletion:       ${PERCENTAGE}%"

# Critical issues
if [ $FAILED -gt 0 ]; then
    echo -e "\n${RED}⚠ CRITICAL ISSUES FOUND${NC}"
    echo -e "Please address the failed items above before proceeding."
    exit 1
fi

# Recommendations
echo -e "\n${BLUE}=== Top Recommendations ===${NC}"
echo -e "1. ${YELLOW}Create automation scripts${NC} (init-backend.sh, deploy-infra-dev.sh, etc.)"
echo -e "2. ${YELLOW}Implement KVS module${NC} for camera streaming functionality"
echo -e "3. ${YELLOW}Add infrastructure testing${NC} (Terratest, tfsec, Checkov)"
echo -e "4. ${YELLOW}Create documentation${NC} (architecture, DR, troubleshooting)"
echo -e "5. ${YELLOW}Add state backup automation${NC} (backup-state.sh)"
echo -e "6. ${YELLOW}Implement drift detection${NC} workflow"

# Terraform-specific checks
echo -e "\n${BLUE}=== Additional Checks ===${NC}"

# Check for backend configuration
TOTAL=$((TOTAL + 1))
if grep -q "backend \"s3\"" "${PROJECT_ROOT}/terraform/environments/dev/main.tf" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} S3 backend configured"
    PASSED=$((PASSED + 1))
else
    echo -e "${YELLOW}⚠${NC} S3 backend not configured"
    WARNINGS=$((WARNINGS + 1))
fi

# Check for required providers
TOTAL=$((TOTAL + 1))
if grep -q "required_providers" "${PROJECT_ROOT}/terraform/environments/dev/main.tf" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} Required providers declared"
    PASSED=$((PASSED + 1))
else
    echo -e "${YELLOW}⚠${NC} Required providers not declared"
    WARNINGS=$((WARNINGS + 1))
fi

# Check module consistency
echo -e "\n${BLUE}=== Module Consistency ===${NC}"
for module in vpc eks rds dynamodb elasticache s3 ecr sqs eventbridge lambda cloudfront waf cloudwatch athena glue cloudtrail monitoring iam bedrock karpenter; do
    TOTAL=$((TOTAL + 3))
    if [ -f "${PROJECT_ROOT}/terraform/modules/${module}/main.tf" ]; then
        PASSED=$((PASSED + 1))
        if [ -f "${PROJECT_ROOT}/terraform/modules/${module}/variables.tf" ]; then
            PASSED=$((PASSED + 1))
        else
            echo -e "${YELLOW}⚠${NC} Module ${module} missing variables.tf"
            WARNINGS=$((WARNINGS + 1))
        fi
        if [ -f "${PROJECT_ROOT}/terraform/modules/${module}/outputs.tf" ]; then
            PASSED=$((PASSED + 1))
        else
            echo -e "${YELLOW}⚠${NC} Module ${module} missing outputs.tf"
            WARNINGS=$((WARNINGS + 1))
        fi
    else
        WARNINGS=$((WARNINGS + 3))
    fi
done

echo -e "\n${GREEN}✓ Infrastructure validation complete${NC}\n"
exit 0
