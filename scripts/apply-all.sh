#!/bin/bash
# Apply terraform changes for all environments

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
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="${AWS_REGION:-ap-northeast-2}"
ENVIRONMENTS=("dev" "prod")

# Usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -e, --env ENV       Apply specific environment only"
    echo "  -y, --yes           Auto-approve all applies"
    echo "  -h, --help          Show this help message"
    echo ""
    echo "WARNING: This will apply changes to production!"
    echo ""
    exit 1
}

# Parse arguments
APPLY_ENV=""
AUTO_APPROVE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--env)
            APPLY_ENV="$2"
            shift 2
            ;;
        -y|--yes)
            AUTO_APPROVE=true
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
echo -e "${BLUE}Terraform Apply - All Environments${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${YELLOW}Account ID:${NC}      ${GREEN}${ACCOUNT_ID}${NC}"
echo -e "${YELLOW}Region:${NC}          ${GREEN}${REGION}${NC}"
echo -e "${YELLOW}Auto-Approve:${NC}    ${GREEN}${AUTO_APPROVE}${NC}"
echo ""

# Determine environments to apply
if [ -n "$APPLY_ENV" ]; then
    ENVIRONMENTS=("$APPLY_ENV")
fi

# Warning for production
if [[ " ${ENVIRONMENTS[@]} " =~ " prod " ]] && [ "$AUTO_APPROVE" = false ]; then
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}WARNING: PRODUCTION DEPLOYMENT${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo "This will modify production infrastructure!"
    echo ""
    read -p "Type 'APPLY PRODUCTION' to confirm: " confirm

    if [ "$confirm" != "APPLY PRODUCTION" ]; then
        echo -e "${YELLOW}Deployment cancelled${NC}"
        exit 0
    fi
    echo ""
fi

# Apply each environment
SUCCESS_COUNT=0
FAIL_COUNT=0
START_TIME=$(date +%s)

for env in "${ENVIRONMENTS[@]}"; do
    ENV_DIR="${PROJECT_ROOT}/terraform/environments/${env}"

    if [ ! -d "$ENV_DIR" ]; then
        echo -e "${YELLOW}!${NC} Environment directory not found: ${env}"
        continue
    fi

    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Applying environment: ${env}${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    cd "$ENV_DIR"

    # Initialize
    echo -e "${BLUE}Initializing...${NC}"
    if ! terraform init \
        -backend-config="bucket=gympt-tfstate-${ACCOUNT_ID}" \
        -backend-config="key=${env}/terraform.tfstate" \
        -backend-config="region=${REGION}" \
        -backend-config="dynamodb_table=gympt-tfstate-lock" \
        > /tmp/tf-init-${env}.log 2>&1; then
        echo -e "${RED}✗${NC} Failed to initialize ${env}"
        echo "  See: /tmp/tf-init-${env}.log"
        ((FAIL_COUNT++))
        continue
    fi

    # Plan
    echo -e "${BLUE}Planning...${NC}"
    PLAN_FILE="/tmp/${env}-apply-$(date +%Y%m%d-%H%M%S).tfplan"

    if ! terraform plan -out="$PLAN_FILE"; then
        echo -e "${RED}✗${NC} Plan failed for ${env}"
        ((FAIL_COUNT++))
        continue
    fi

    # Confirm for this environment
    if [ "$AUTO_APPROVE" = false ]; then
        echo ""
        read -p "Apply this plan for ${env}? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            echo -e "${YELLOW}Skipped ${env}${NC}"
            continue
        fi
    fi

    # Apply
    echo ""
    echo -e "${BLUE}Applying...${NC}"
    ENV_START=$(date +%s)

    if terraform apply "$PLAN_FILE"; then
        ENV_END=$(date +%s)
        DURATION=$((ENV_END - ENV_START))
        echo -e "${GREEN}✓${NC} Successfully applied ${env} (${DURATION}s)"
        ((SUCCESS_COUNT++))

        # Save outputs
        OUTPUT_DIR="${PROJECT_ROOT}/outputs"
        mkdir -p "$OUTPUT_DIR"
        terraform output -json > "${OUTPUT_DIR}/${env}-outputs.json"
        echo -e "  Outputs saved to: ${OUTPUT_DIR}/${env}-outputs.json"
    else
        echo -e "${RED}✗${NC} Apply failed for ${env}"
        ((FAIL_COUNT++))
    fi

    echo ""
    echo "----------------------------------------"
    echo ""
done

END_TIME=$(date +%s)
TOTAL_DURATION=$((END_TIME - START_TIME))

# Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Apply Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}✓${NC} Successful:    ${SUCCESS_COUNT}"
echo -e "${RED}✗${NC} Failed:        ${FAIL_COUNT}"
echo -e "${YELLOW}⏱${NC}  Total Time:   ${TOTAL_DURATION}s"
echo ""

if [ $SUCCESS_COUNT -gt 0 ]; then
    echo -e "${BLUE}Next Steps:${NC}"
    echo -e "  1. Update kubeconfigs:  ${YELLOW}./scripts/get-kubeconfig.sh dev${NC}"
    echo -e "  2. Deploy applications: ${YELLOW}kubectl apply -k k8s/environments/dev${NC}"
    echo -e "  3. Verify deployment:   ${YELLOW}kubectl get all -A${NC}"
    echo ""
fi

if [ $FAIL_COUNT -gt 0 ]; then
    exit 1
fi
