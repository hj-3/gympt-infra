#!/bin/bash
# Deploy dev environment infrastructure

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV="dev"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")
REGION="${AWS_REGION:-ap-northeast-2}"

# Usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -y, --yes           Auto-approve terraform apply"
    echo "  -p, --plan-only     Only run terraform plan"
    echo "  -d, --destroy       Destroy infrastructure"
    echo "  -h, --help          Show this help message"
    echo ""
    exit 1
}

# Parse arguments
AUTO_APPROVE=false
PLAN_ONLY=false
DESTROY_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -y|--yes)
            AUTO_APPROVE=true
            shift
            ;;
        -p|--plan-only)
            PLAN_ONLY=true
            shift
            ;;
        -d|--destroy)
            DESTROY_MODE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            ;;
    esac
done

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}GYMPT Infrastructure Deployment${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${YELLOW}Environment:${NC}     ${GREEN}${ENV}${NC}"
echo -e "${YELLOW}Account ID:${NC}      ${GREEN}${ACCOUNT_ID}${NC}"
echo -e "${YELLOW}Region:${NC}          ${GREEN}${REGION}${NC}"
echo -e "${YELLOW}Destroy Mode:${NC}    ${GREEN}${DESTROY_MODE}${NC}"
echo ""

# Verify AWS credentials
echo -e "${BLUE}[1/5]${NC} Verifying AWS credentials..."
if ! aws sts get-caller-identity &>/dev/null; then
    echo -e "${RED}Error: AWS credentials not configured${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} AWS credentials verified"

# Navigate to environment directory
ENV_DIR="${PROJECT_ROOT}/terraform/environments/${ENV}"
if [ ! -d "$ENV_DIR" ]; then
    echo -e "${RED}Error: Environment directory not found: ${ENV_DIR}${NC}"
    exit 1
fi

cd "$ENV_DIR"

# Initialize Terraform
echo -e "${BLUE}[2/5]${NC} Initializing Terraform..."
terraform init \
    -backend-config="bucket=gympt-tfstate-${ACCOUNT_ID}" \
    -backend-config="key=${ENV}/terraform.tfstate" \
    -backend-config="region=${REGION}" \
    -backend-config="dynamodb_table=gympt-tfstate-lock" \
    -upgrade

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Terraform initialization failed${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Terraform initialized"

# Validate configuration
echo -e "${BLUE}[3/5]${NC} Validating Terraform configuration..."
terraform validate
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Terraform validation failed${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Configuration validated"

# Plan
echo -e "${BLUE}[4/5]${NC} Creating execution plan..."
if [ "$DESTROY_MODE" = true ]; then
    terraform plan -destroy -out=tfplan
else
    terraform plan -out=tfplan
fi

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Terraform plan failed${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Execution plan created"

# Exit if plan-only mode
if [ "$PLAN_ONLY" = true ]; then
    echo ""
    echo -e "${GREEN}Plan-only mode: Exiting without applying changes${NC}"
    exit 0
fi

# Confirm before apply
echo -e "${BLUE}[5/5]${NC} Applying infrastructure changes..."
if [ "$AUTO_APPROVE" = false ]; then
    echo ""
    echo -e "${YELLOW}WARNING: This will modify your AWS infrastructure!${NC}"
    read -p "Do you want to apply these changes? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo -e "${YELLOW}Deployment cancelled${NC}"
        exit 0
    fi
fi

# Apply
START_TIME=$(date +%s)

if [ "$DESTROY_MODE" = true ]; then
    terraform apply tfplan
else
    terraform apply tfplan
fi

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Terraform apply failed${NC}"
    exit 1
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${YELLOW}Duration:${NC} ${DURATION} seconds"
echo ""

# Show outputs
if [ "$DESTROY_MODE" = false ]; then
    echo -e "${BLUE}Key Outputs:${NC}"
    terraform output
    echo ""

    # Save outputs to file
    OUTPUT_FILE="${PROJECT_ROOT}/outputs/${ENV}-outputs.json"
    mkdir -p "${PROJECT_ROOT}/outputs"
    terraform output -json > "$OUTPUT_FILE"
    echo -e "${GREEN}✓${NC} Outputs saved to: ${OUTPUT_FILE}"
    echo ""

    # Show next steps
    echo -e "${BLUE}Next Steps:${NC}"
    echo -e "  1. Update kubeconfig:      ${YELLOW}./scripts/get-kubeconfig.sh ${ENV}${NC}"
    echo -e "  2. Deploy applications:    ${YELLOW}cd ../k8s && kubectl apply -k environments/${ENV}${NC}"
    echo -e "  3. Check cluster status:   ${YELLOW}kubectl get nodes${NC}"
    echo ""
fi
