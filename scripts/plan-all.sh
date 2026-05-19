#!/bin/bash
# Run terraform plan for all environments

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
    echo "  -e, --env ENV       Plan specific environment only"
    echo "  -d, --destroy       Run destroy plan"
    echo "  -h, --help          Show this help message"
    echo ""
    exit 1
}

# Parse arguments
PLAN_ENV=""
DESTROY_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--env)
            PLAN_ENV="$2"
            shift 2
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
echo -e "${BLUE}Terraform Plan - All Environments${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${YELLOW}Account ID:${NC}      ${GREEN}${ACCOUNT_ID}${NC}"
echo -e "${YELLOW}Region:${NC}          ${GREEN}${REGION}${NC}"
echo -e "${YELLOW}Destroy Mode:${NC}    ${GREEN}${DESTROY_MODE}${NC}"
echo ""

# Determine environments to plan
if [ -n "$PLAN_ENV" ]; then
    ENVIRONMENTS=("$PLAN_ENV")
fi

# Plan each environment
SUCCESS_COUNT=0
FAIL_COUNT=0

for env in "${ENVIRONMENTS[@]}"; do
    ENV_DIR="${PROJECT_ROOT}/terraform/environments/${env}"

    if [ ! -d "$ENV_DIR" ]; then
        echo -e "${YELLOW}!${NC} Environment directory not found: ${env}"
        continue
    fi

    echo -e "${BLUE}Planning environment: ${env}${NC}"
    echo ""

    cd "$ENV_DIR"

    # Initialize
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
    PLAN_FILE="${env}-plan-$(date +%Y%m%d-%H%M%S).tfplan"

    if [ "$DESTROY_MODE" = true ]; then
        terraform plan -destroy -out="$PLAN_FILE"
    else
        terraform plan -out="$PLAN_FILE"
    fi

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${NC} Plan succeeded for ${env}"
        echo -e "  Plan file: ${PLAN_FILE}"
        ((SUCCESS_COUNT++))
    else
        echo -e "${RED}✗${NC} Plan failed for ${env}"
        ((FAIL_COUNT++))
    fi

    echo ""
    echo "----------------------------------------"
    echo ""
done

# Summary
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Plan Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}✓${NC} Successful: ${SUCCESS_COUNT}"
echo -e "${RED}✗${NC} Failed:     ${FAIL_COUNT}"
echo ""

if [ $FAIL_COUNT -gt 0 ]; then
    exit 1
fi
