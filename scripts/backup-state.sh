#!/bin/bash
# Backup Terraform state files to separate backup bucket

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
SOURCE_BUCKET="gympt-tfstate-${ACCOUNT_ID}"
BACKUP_BUCKET="gympt-tfstate-backup-${ACCOUNT_ID}"
REGION="${AWS_REGION:-ap-northeast-2}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
ENVIRONMENTS=("dev" "prod")

# Usage information
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -e, --env ENV       Backup specific environment (default: all)"
    echo "  -l, --list          List existing backups"
    echo "  -r, --restore ENV   Restore state from latest backup"
    echo "  -h, --help          Show this help message"
    echo ""
    exit 1
}

# Parse arguments
BACKUP_ENV=""
LIST_MODE=false
RESTORE_MODE=false
RESTORE_ENV=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--env)
            BACKUP_ENV="$2"
            shift 2
            ;;
        -l|--list)
            LIST_MODE=true
            shift
            ;;
        -r|--restore)
            RESTORE_MODE=true
            RESTORE_ENV="$2"
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

# List backups mode
if [ "$LIST_MODE" = true ]; then
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Terraform State Backups${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    if ! aws s3 ls "s3://${BACKUP_BUCKET}/" &>/dev/null; then
        echo -e "${YELLOW}No backup bucket found${NC}"
        exit 0
    fi

    for env in "${ENVIRONMENTS[@]}"; do
        echo -e "${YELLOW}Environment: ${env}${NC}"
        aws s3 ls "s3://${BACKUP_BUCKET}/${env}/" --human-readable --summarize || echo "  No backups"
        echo ""
    done
    exit 0
fi

# Restore mode
if [ "$RESTORE_MODE" = true ]; then
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Restore Terraform State${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo -e "${YELLOW}Environment:${NC}     ${GREEN}${RESTORE_ENV}${NC}"
    echo ""

    # Find latest backup
    LATEST_BACKUP=$(aws s3 ls "s3://${BACKUP_BUCKET}/${RESTORE_ENV}/" | sort | tail -1 | awk '{print $4}')

    if [ -z "$LATEST_BACKUP" ]; then
        echo -e "${RED}Error: No backup found for environment '${RESTORE_ENV}'${NC}"
        exit 1
    fi

    echo -e "${YELLOW}Latest backup:${NC}   ${GREEN}${LATEST_BACKUP}${NC}"
    echo ""
    echo -e "${RED}WARNING: This will overwrite the current state file!${NC}"
    read -p "Continue? (yes/no): " confirm

    if [ "$confirm" != "yes" ]; then
        echo -e "${YELLOW}Restore cancelled${NC}"
        exit 0
    fi

    # Backup current state first
    SAFETY_BACKUP="${RESTORE_ENV}/terraform.tfstate.pre-restore-${TIMESTAMP}"
    echo -e "${BLUE}Creating safety backup...${NC}"
    aws s3 cp \
        "s3://${SOURCE_BUCKET}/${RESTORE_ENV}/terraform.tfstate" \
        "s3://${BACKUP_BUCKET}/${SAFETY_BACKUP}" \
        --region "${REGION}" || true

    # Restore
    echo -e "${BLUE}Restoring state...${NC}"
    aws s3 cp \
        "s3://${BACKUP_BUCKET}/${RESTORE_ENV}/${LATEST_BACKUP}" \
        "s3://${SOURCE_BUCKET}/${RESTORE_ENV}/terraform.tfstate" \
        --region "${REGION}"

    echo -e "${GREEN}✓${NC} State restored from: ${LATEST_BACKUP}"
    echo -e "${GREEN}✓${NC} Safety backup saved to: ${SAFETY_BACKUP}"
    exit 0
fi

# Backup mode
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Terraform State Backup${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${YELLOW}Source Bucket:${NC}   ${GREEN}${SOURCE_BUCKET}${NC}"
echo -e "${YELLOW}Backup Bucket:${NC}   ${GREEN}${BACKUP_BUCKET}${NC}"
echo -e "${YELLOW}Timestamp:${NC}       ${GREEN}${TIMESTAMP}${NC}"
echo ""

# Verify AWS credentials
echo -e "${BLUE}[1/4]${NC} Verifying AWS credentials..."
if ! aws sts get-caller-identity &>/dev/null; then
    echo -e "${RED}Error: AWS credentials not configured${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} AWS credentials verified"

# Create backup bucket if not exists
echo -e "${BLUE}[2/4]${NC} Checking backup bucket..."
if ! aws s3 ls "s3://${BACKUP_BUCKET}" 2>/dev/null; then
    echo -e "${YELLOW}Creating backup bucket...${NC}"

    if [ "$REGION" = "us-east-1" ]; then
        aws s3api create-bucket \
            --bucket "${BACKUP_BUCKET}" \
            --region "${REGION}"
    else
        aws s3api create-bucket \
            --bucket "${BACKUP_BUCKET}" \
            --region "${REGION}" \
            --create-bucket-configuration LocationConstraint="${REGION}"
    fi

    # Enable versioning
    aws s3api put-bucket-versioning \
        --bucket "${BACKUP_BUCKET}" \
        --versioning-configuration Status=Enabled

    # Enable encryption
    aws s3api put-bucket-encryption \
        --bucket "${BACKUP_BUCKET}" \
        --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                },
                "BucketKeyEnabled": true
            }]
        }'

    # Add lifecycle policy
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "${BACKUP_BUCKET}" \
        --lifecycle-configuration '{
            "Rules": [{
                "Id": "DeleteOldBackups",
                "Status": "Enabled",
                "Expiration": {
                    "Days": 90
                }
            }]
        }'

    echo -e "${GREEN}✓${NC} Backup bucket created"
else
    echo -e "${GREEN}✓${NC} Backup bucket exists"
fi

# Determine environments to backup
if [ -n "$BACKUP_ENV" ]; then
    ENVIRONMENTS=("$BACKUP_ENV")
fi

# Backup state files
echo -e "${BLUE}[3/4]${NC} Backing up state files..."

BACKUP_COUNT=0
for env in "${ENVIRONMENTS[@]}"; do
    SOURCE_KEY="${env}/terraform.tfstate"
    BACKUP_KEY="${env}/terraform.tfstate.${TIMESTAMP}"

    if aws s3 ls "s3://${SOURCE_BUCKET}/${SOURCE_KEY}" 2>/dev/null; then
        aws s3 cp \
            "s3://${SOURCE_BUCKET}/${SOURCE_KEY}" \
            "s3://${BACKUP_BUCKET}/${BACKUP_KEY}" \
            --region "${REGION}"

        echo -e "${GREEN}✓${NC} Backed up: ${env}"
        ((BACKUP_COUNT++))
    else
        echo -e "${YELLOW}!${NC} No state file for: ${env}"
    fi
done

# Show backup summary
echo -e "${BLUE}[4/4]${NC} Generating backup report..."
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Backup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${YELLOW}Backed up:${NC}       ${GREEN}${BACKUP_COUNT} state file(s)${NC}"
echo -e "${YELLOW}Timestamp:${NC}       ${GREEN}${TIMESTAMP}${NC}"
echo ""

# List backups
echo -e "${BLUE}Recent Backups:${NC}"
for env in "${ENVIRONMENTS[@]}"; do
    echo -e "${YELLOW}${env}:${NC}"
    aws s3 ls "s3://${BACKUP_BUCKET}/${env}/" --recursive --human-readable | tail -5 || echo "  No backups"
    echo ""
done

echo -e "${BLUE}Restore Command:${NC}"
echo -e "  ${YELLOW}$0 --restore <environment>${NC}"
echo ""
