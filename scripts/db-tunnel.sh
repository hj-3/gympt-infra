#!/bin/bash
# Create SSM tunnel to RDS database via EKS node

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
ENV="${1:-dev}"
LOCAL_PORT="${2:-5432}"
REGION="${AWS_REGION:-ap-northeast-2}"

# Usage information
usage() {
    echo "Usage: $0 [ENVIRONMENT] [LOCAL_PORT]"
    echo ""
    echo "Arguments:"
    echo "  ENVIRONMENT    Environment name (default: dev)"
    echo "  LOCAL_PORT     Local port for tunnel (default: 5432)"
    echo ""
    echo "Examples:"
    echo "  $0              # Connect to dev on port 5432"
    echo "  $0 prod         # Connect to prod on port 5432"
    echo "  $0 dev 15432    # Connect to dev on port 15432"
    echo ""
    exit 1
}

if [ "$ENV" = "-h" ] || [ "$ENV" = "--help" ]; then
    usage
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}RDS Database Tunnel${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${YELLOW}Environment:${NC}     ${GREEN}${ENV}${NC}"
echo -e "${YELLOW}Local Port:${NC}      ${GREEN}${LOCAL_PORT}${NC}"
echo ""

# Verify AWS credentials
echo -e "${BLUE}[1/5]${NC} Verifying AWS credentials..."
if ! aws sts get-caller-identity &>/dev/null; then
    echo -e "${RED}Error: AWS credentials not configured${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} AWS credentials verified"

# Check if SSM plugin is installed
echo -e "${BLUE}[2/5]${NC} Checking AWS Session Manager plugin..."
if ! command -v session-manager-plugin &> /dev/null; then
    echo -e "${RED}Error: AWS Session Manager plugin is not installed${NC}"
    echo ""
    echo "Install instructions:"
    echo "  https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"
    exit 1
fi
echo -e "${GREEN}✓${NC} Session Manager plugin installed"

# Find bastion instance (any EKS node with SSM agent)
echo -e "${BLUE}[3/5]${NC} Finding bastion instance..."
INSTANCE_ID=$(aws ec2 describe-instances \
    --region "${REGION}" \
    --filters \
        "Name=tag:eks:cluster-name,Values=gympt-${ENV}-eks" \
        "Name=instance-state-name,Values=running" \
    --query "Reservations[0].Instances[0].InstanceId" \
    --output text)

if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" = "None" ]; then
    echo -e "${RED}Error: No running EKS instances found${NC}"
    echo ""
    echo "Available instances:"
    aws ec2 describe-instances \
        --region "${REGION}" \
        --filters "Name=tag:eks:cluster-name,Values=gympt-${ENV}-cluster" \
        --query "Reservations[*].Instances[*].[InstanceId,State.Name,PrivateIpAddress]" \
        --output table
    exit 1
fi

echo -e "${GREEN}✓${NC} Found instance: ${INSTANCE_ID}"

# Get RDS endpoint
echo -e "${BLUE}[4/5]${NC} Getting RDS endpoint..."
RDS_ENDPOINT=$(aws rds describe-db-instances \
    --region "${REGION}" \
    --db-instance-identifier "gympt-${ENV}-postgres" \
    --query "DBInstances[0].Endpoint.Address" \
    --output text 2>/dev/null)

if [ -z "$RDS_ENDPOINT" ] || [ "$RDS_ENDPOINT" = "None" ]; then
    echo -e "${YELLOW}Warning: RDS instance identifier 'gympt-${ENV}-postgres' not found${NC}"
    echo -e "${YELLOW}Trying alternative naming pattern...${NC}"

    # Try cluster endpoint
    RDS_ENDPOINT=$(aws rds describe-db-clusters \
        --region "${REGION}" \
        --db-cluster-identifier "gympt-${ENV}-cluster" \
        --query "DBClusters[0].Endpoint" \
        --output text 2>/dev/null)

    if [ -z "$RDS_ENDPOINT" ] || [ "$RDS_ENDPOINT" = "None" ]; then
        echo -e "${RED}Error: Could not find RDS endpoint${NC}"
        echo ""
        echo "Available RDS instances:"
        aws rds describe-db-instances --region "${REGION}" --query "DBInstances[*].[DBInstanceIdentifier,Endpoint.Address]" --output table
        exit 1
    fi
fi

echo -e "${GREEN}✓${NC} RDS endpoint: ${RDS_ENDPOINT}"

# Get database credentials from Secrets Manager
echo -e "${BLUE}[5/5]${NC} Retrieving database credentials..."
SECRET_ARN=$(aws secretsmanager list-secrets \
    --region "${REGION}" \
    --filters Key=name,Values="gympt-${ENV}-db-credentials" \
    --query "SecretList[0].ARN" \
    --output text 2>/dev/null)

if [ -n "$SECRET_ARN" ] && [ "$SECRET_ARN" != "None" ]; then
    DB_USER=$(aws secretsmanager get-secret-value \
        --region "${REGION}" \
        --secret-id "$SECRET_ARN" \
        --query "SecretString" \
        --output text | grep -o '"username":"[^"]*' | cut -d'"' -f4)

    DB_NAME=$(aws secretsmanager get-secret-value \
        --region "${REGION}" \
        --secret-id "$SECRET_ARN" \
        --query "SecretString" \
        --output text | grep -o '"database":"[^"]*' | cut -d'"' -f4)

    if [ -z "$DB_USER" ]; then
        DB_USER="gympt_admin"
    fi
    if [ -z "$DB_NAME" ]; then
        DB_NAME="gympt"
    fi
else
    DB_USER="gympt_admin"
    DB_NAME="gympt"
fi

echo -e "${GREEN}✓${NC} Database user: ${DB_USER}"
echo -e "${GREEN}✓${NC} Database name: ${DB_NAME}"

# Check if port is already in use
if lsof -Pi :${LOCAL_PORT} -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo ""
    echo -e "${RED}Error: Port ${LOCAL_PORT} is already in use${NC}"
    echo ""
    echo "Processes using port ${LOCAL_PORT}:"
    lsof -Pi :${LOCAL_PORT} -sTCP:LISTEN
    echo ""
    echo "Try a different port: $0 ${ENV} <port>"
    exit 1
fi

# Display connection information
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Tunnel Configuration${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${YELLOW}Instance ID:${NC}     ${GREEN}${INSTANCE_ID}${NC}"
echo -e "${YELLOW}RDS Endpoint:${NC}    ${GREEN}${RDS_ENDPOINT}:5432${NC}"
echo -e "${YELLOW}Local Port:${NC}      ${GREEN}${LOCAL_PORT}${NC}"
echo ""
echo -e "${BLUE}Connection String:${NC}"
echo -e "  ${YELLOW}psql -h localhost -p ${LOCAL_PORT} -U ${DB_USER} -d ${DB_NAME}${NC}"
echo ""
echo -e "${BLUE}Connection URL:${NC}"
echo -e "  ${YELLOW}postgresql://${DB_USER}@localhost:${LOCAL_PORT}/${DB_NAME}${NC}"
echo ""
echo -e "${BLUE}PgAdmin/DBeaver:${NC}"
echo -e "  Host:     ${YELLOW}localhost${NC}"
echo -e "  Port:     ${YELLOW}${LOCAL_PORT}${NC}"
echo -e "  Database: ${YELLOW}${DB_NAME}${NC}"
echo -e "  Username: ${YELLOW}${DB_USER}${NC}"
echo ""
echo -e "${YELLOW}Starting tunnel... (Press Ctrl+C to exit)${NC}"
echo ""

# Start SSM session
aws ssm start-session \
    --region "${REGION}" \
    --target "${INSTANCE_ID}" \
    --document-name AWS-StartPortForwardingSessionToRemoteHost \
    --parameters "{\"host\":[\"${RDS_ENDPOINT}\"],\"portNumber\":[\"5432\"],\"localPortNumber\":[\"${LOCAL_PORT}\"]}"
