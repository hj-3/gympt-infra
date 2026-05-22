#!/bin/bash
# Initialize Terraform S3 backend and DynamoDB state locking

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="gympt-tfstate-${ACCOUNT_ID}"
DYNAMODB_TABLE="gympt-tfstate-lock"
REGION="${AWS_REGION:-ap-northeast-2}"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Terraform Backend Initialization${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${YELLOW}Configuration:${NC}"
echo -e "  Account ID:      ${GREEN}${ACCOUNT_ID}${NC}"
echo -e "  Bucket:          ${GREEN}${BUCKET_NAME}${NC}"
echo -e "  DynamoDB Table:  ${GREEN}${DYNAMODB_TABLE}${NC}"
echo -e "  Region:          ${GREEN}${REGION}${NC}"
echo ""

# Verify AWS credentials
echo -e "${BLUE}[1/6]${NC} Verifying AWS credentials..."
if ! aws sts get-caller-identity &>/dev/null; then
    echo -e "${RED}Error: AWS credentials not configured${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} AWS credentials verified"

# Create S3 bucket
echo -e "${BLUE}[2/6]${NC} Creating S3 bucket..."
if aws s3 ls "s3://${BUCKET_NAME}" 2>/dev/null; then
    echo -e "${YELLOW}!${NC} S3 bucket already exists"
else
    if [ "$REGION" = "us-east-1" ]; then
        aws s3api create-bucket \
            --bucket "${BUCKET_NAME}" \
            --region "${REGION}"
    else
        aws s3api create-bucket \
            --bucket "${BUCKET_NAME}" \
            --region "${REGION}" \
            --create-bucket-configuration LocationConstraint="${REGION}"
    fi
    echo -e "${GREEN}✓${NC} S3 bucket created"
fi

# Enable versioning
echo -e "${BLUE}[3/6]${NC} Enabling bucket versioning..."
aws s3api put-bucket-versioning \
    --bucket "${BUCKET_NAME}" \
    --versioning-configuration Status=Enabled
echo -e "${GREEN}✓${NC} Versioning enabled"

# Enable encryption
echo -e "${BLUE}[4/6]${NC} Enabling bucket encryption..."
aws s3api put-bucket-encryption \
    --bucket "${BUCKET_NAME}" \
    --server-side-encryption-configuration '{
        "Rules": [{
            "ApplyServerSideEncryptionByDefault": {
                "SSEAlgorithm": "AES256"
            },
            "BucketKeyEnabled": true
        }]
    }'
echo -e "${GREEN}✓${NC} Encryption enabled"

# Block public access
echo -e "${BLUE}[5/6]${NC} Configuring bucket security..."
aws s3api put-public-access-block \
    --bucket "${BUCKET_NAME}" \
    --public-access-block-configuration \
        BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# Add lifecycle policy
aws s3api put-bucket-lifecycle-configuration \
    --bucket "${BUCKET_NAME}" \
    --lifecycle-configuration '{
        "Rules": [{
            "ID": "DeleteOldVersions",
            "Status": "Enabled",
            "Filter": {},
            "NoncurrentVersionExpiration": {
                "NoncurrentDays": 90
            }
        }]
    }'
echo -e "${GREEN}✓${NC} Security and lifecycle policies configured"

# Create DynamoDB table for state locking
echo -e "${BLUE}[6/6]${NC} Creating DynamoDB table..."
if aws dynamodb describe-table --table-name "${DYNAMODB_TABLE}" --region "${REGION}" >/dev/null 2>&1; then
    echo -e "${YELLOW}!${NC} DynamoDB table already exists"
else
    aws dynamodb create-table \
        --table-name "${DYNAMODB_TABLE}" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region "${REGION}" \
        --tags Key=Project,Value=gympt Key=ManagedBy,Value=script >/dev/null 2>&1

    echo -e "${YELLOW}Waiting for table to be active (max 30s)...${NC}"
    for i in {1..30}; do
        STATUS=$(aws dynamodb describe-table --table-name "${DYNAMODB_TABLE}" --region "${REGION}" --query 'Table.TableStatus' --output text 2>/dev/null)
        if [ "$STATUS" = "ACTIVE" ]; then
            echo -e "${GREEN}✓${NC} DynamoDB table created"
            break
        fi
        sleep 1
    done

    if [ "$STATUS" != "ACTIVE" ]; then
        echo -e "${YELLOW}⚠${NC} Table is being created (Status: ${STATUS}). It will be ready soon."
    fi
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Backend Initialization Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Add this to your Terraform backend configuration:${NC}"
echo ""
echo -e "${BLUE}terraform {${NC}"
echo -e "${BLUE}  backend \"s3\" {${NC}"
echo -e "${BLUE}    bucket         = \"${BUCKET_NAME}\"${NC}"
echo -e "${BLUE}    key            = \"ENV/terraform.tfstate\"${NC}"
echo -e "${BLUE}    region         = \"${REGION}\"${NC}"
echo -e "${BLUE}    dynamodb_table = \"${DYNAMODB_TABLE}\"${NC}"
echo -e "${BLUE}    encrypt        = true${NC}"
echo -e "${BLUE}  }${NC}"
echo -e "${BLUE}}${NC}"
echo ""
