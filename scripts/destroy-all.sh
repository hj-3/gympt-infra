#!/bin/bash
# Destroy all infrastructure (USE WITH EXTREME CAUTION)

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
    echo "  -e, --env ENV       Destroy specific environment only"
    echo "  -h, --help          Show this help message"
    echo ""
    echo "DANGER: This will destroy all infrastructure!"
    echo ""
    exit 1
}

# Parse arguments
DESTROY_ENV=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--env)
            DESTROY_ENV="$2"
            shift 2
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

echo -e "${RED}========================================${NC}"
echo -e "${RED}DANGER: INFRASTRUCTURE DESTRUCTION${NC}"
echo -e "${RED}========================================${NC}"
echo ""
echo -e "${YELLOW}Account ID:${NC}      ${GREEN}${ACCOUNT_ID}${NC}"
echo -e "${YELLOW}Region:${NC}          ${GREEN}${REGION}${NC}"
echo ""

# Determine environments to destroy
if [ -n "$DESTROY_ENV" ]; then
    ENVIRONMENTS=("$DESTROY_ENV")
fi

# Critical warning
echo -e "${RED}This will PERMANENTLY DELETE:${NC}"
for env in "${ENVIRONMENTS[@]}"; do
    echo -e "  - ${env} environment"
    echo -e "    • EKS cluster and all workloads"
    echo -e "    • RDS databases (with data)"
    echo -e "    • S3 buckets (with data)"
    echo -e "    • ElastiCache clusters"
    echo -e "    • KVS streams"
    echo -e "    • All other AWS resources"
done
echo ""

# First confirmation
echo -e "${RED}WARNING: THIS ACTION CANNOT BE UNDONE!${NC}"
echo ""
read -p "Are you ABSOLUTELY sure? (type 'yes' to continue): " confirm1

if [ "$confirm1" != "yes" ]; then
    echo -e "${GREEN}Destruction cancelled${NC}"
    exit 0
fi

# Second confirmation with environment name
echo ""
for env in "${ENVIRONMENTS[@]}"; do
    read -p "Type the environment name '$env' to confirm: " confirm2
    if [ "$confirm2" != "$env" ]; then
        echo -e "${GREEN}Destruction cancelled${NC}"
        exit 0
    fi
done

# Final confirmation for production
if [[ " ${ENVIRONMENTS[@]} " =~ " prod " ]]; then
    echo ""
    echo -e "${RED}FINAL WARNING: DESTROYING PRODUCTION${NC}"
    read -p "Type 'DESTROY PRODUCTION' to confirm: " confirm3

    if [ "$confirm3" != "DESTROY PRODUCTION" ]; then
        echo -e "${GREEN}Destruction cancelled${NC}"
        exit 0
    fi
fi

echo ""
echo -e "${YELLOW}Creating backup of current state...${NC}"
"${SCRIPT_DIR}/backup-state.sh" || true

echo ""
echo -e "${RED}Starting destruction in 10 seconds... (Ctrl+C to cancel)${NC}"
for i in {10..1}; do
    echo -ne "${RED}${i}...${NC} "
    sleep 1
done
echo ""
echo ""

# Destroy each environment
SUCCESS_COUNT=0
FAIL_COUNT=0
START_TIME=$(date +%s)

for env in "${ENVIRONMENTS[@]}"; do
    ENV_DIR="${PROJECT_ROOT}/terraform/environments/${env}"

    if [ ! -d "$ENV_DIR" ]; then
        echo -e "${YELLOW}!${NC} Environment directory not found: ${env}"
        continue
    fi

    echo -e "${RED}========================================${NC}"
    echo -e "${RED}Destroying environment: ${env}${NC}"
    echo -e "${RED}========================================${NC}"
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

    # Destroy
    echo -e "${RED}Destroying...${NC}"
    ENV_START=$(date +%s)

    if terraform destroy -auto-approve; then
        ENV_END=$(date +%s)
        DURATION=$((ENV_END - ENV_START))
        echo -e "${GREEN}✓${NC} Successfully destroyed ${env} (${DURATION}s)"
        ((SUCCESS_COUNT++))
    else
        echo -e "${RED}✗${NC} Destroy failed for ${env}"
        echo ""
        echo -e "${YELLOW}Some resources may have been deleted.${NC}"
        echo -e "${YELLOW}Run again to clean up remaining resources.${NC}"
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
echo -e "${BLUE}Destruction Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}✓${NC} Successful:    ${SUCCESS_COUNT}"
echo -e "${RED}✗${NC} Failed:        ${FAIL_COUNT}"
echo -e "${YELLOW}⏱${NC}  Total Time:   ${TOTAL_DURATION}s"
echo ""

if [ $SUCCESS_COUNT -gt 0 ]; then
    echo -e "${YELLOW}Destroyed environments: ${ENVIRONMENTS[*]}${NC}"
    echo ""
    echo -e "${BLUE}Note:${NC} State files are preserved in S3"
    echo -e "${BLUE}Note:${NC} Backup created before destruction"
    echo ""
fi

if [ $FAIL_COUNT -gt 0 ]; then
    echo -e "${RED}Some resources may still exist.${NC}"
    echo -e "${YELLOW}Check AWS console and run script again if needed.${NC}"
    echo ""
    exit 1
fi
