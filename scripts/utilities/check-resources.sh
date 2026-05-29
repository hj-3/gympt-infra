#!/bin/bash
# Check status of all GYMPT AWS resources

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
ENV="${1:-dev}"
REGION="${AWS_REGION:-ap-northeast-2}"
TIMESTAMP=$(date +%Y-%m-%d\ %H:%M:%S)

# Usage information
usage() {
    echo "Usage: $0 [ENVIRONMENT]"
    echo ""
    echo "Arguments:"
    echo "  ENVIRONMENT    Environment name (default: dev)"
    echo ""
    echo "Examples:"
    echo "  $0              # Check dev resources"
    echo "  $0 prod         # Check prod resources"
    echo ""
    exit 1
}

if [ "$ENV" = "-h" ] || [ "$ENV" = "--help" ]; then
    usage
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}GYMPT Resource Status Check${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${YELLOW}Environment:${NC}     ${GREEN}${ENV}${NC}"
echo -e "${YELLOW}Region:${NC}          ${GREEN}${REGION}${NC}"
echo -e "${YELLOW}Timestamp:${NC}       ${GREEN}${TIMESTAMP}${NC}"
echo ""

# Verify AWS credentials
if ! aws sts get-caller-identity &>/dev/null; then
    echo -e "${RED}Error: AWS credentials not configured${NC}"
    exit 1
fi

# Helper function to format status
format_status() {
    local status=$1
    case $status in
        *"ACTIVE"*|*"available"*|*"running"*|*"Ready"*)
            echo -e "${GREEN}${status}${NC}"
            ;;
        *"CREATING"*|*"creating"*|*"pending"*)
            echo -e "${YELLOW}${status}${NC}"
            ;;
        *"FAILED"*|*"failed"*|*"error"*|*"DEGRADED"*)
            echo -e "${RED}${status}${NC}"
            ;;
        *)
            echo -e "${status}"
            ;;
    esac
}

# Check VPC
echo -e "${BLUE}[1/12] VPC${NC}"
VPC_ID=$(aws ec2 describe-vpcs \
    --region "$REGION" \
    --filters "Name=tag:Name,Values=gympt-${ENV}-vpc" \
    --query "Vpcs[0].VpcId" \
    --output text 2>/dev/null)

if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
    echo -e "  VPC ID:     ${GREEN}${VPC_ID}${NC}"

    # Count subnets
    SUBNET_COUNT=$(aws ec2 describe-subnets \
        --region "$REGION" \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
        --query "length(Subnets)" \
        --output text)
    echo -e "  Subnets:    ${GREEN}${SUBNET_COUNT}${NC}"
else
    echo -e "  ${RED}Not found${NC}"
fi
echo ""

# Check EKS Cluster
echo -e "${BLUE}[2/12] EKS Cluster${NC}"
CLUSTER_NAME="gympt-${ENV}-cluster"
CLUSTER_STATUS=$(aws eks describe-cluster \
    --region "$REGION" \
    --name "$CLUSTER_NAME" \
    --query "cluster.status" \
    --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$CLUSTER_STATUS" != "NOT_FOUND" ]; then
    echo -e "  Cluster:    ${GREEN}${CLUSTER_NAME}${NC}"
    echo -e "  Status:     $(format_status ${CLUSTER_STATUS})"

    # Get node count
    NODE_COUNT=$(aws eks describe-nodegroup \
        --region "$REGION" \
        --cluster-name "$CLUSTER_NAME" \
        --nodegroup-name "gympt-${ENV}-workers" \
        --query "nodegroup.scalingConfig.desiredSize" \
        --output text 2>/dev/null || echo "0")
    echo -e "  Nodes:      ${GREEN}${NODE_COUNT}${NC}"

    # Get Kubernetes version
    K8S_VERSION=$(aws eks describe-cluster \
        --region "$REGION" \
        --name "$CLUSTER_NAME" \
        --query "cluster.version" \
        --output text 2>/dev/null)
    echo -e "  Version:    ${GREEN}${K8S_VERSION}${NC}"
else
    echo -e "  ${RED}Not found${NC}"
fi
echo ""

# Check RDS
echo -e "${BLUE}[3/12] RDS Database${NC}"
RDS_ID="gympt-${ENV}-postgres"
RDS_STATUS=$(aws rds describe-db-instances \
    --region "$REGION" \
    --db-instance-identifier "$RDS_ID" \
    --query "DBInstances[0].DBInstanceStatus" \
    --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$RDS_STATUS" != "NOT_FOUND" ]; then
    echo -e "  Instance:   ${GREEN}${RDS_ID}${NC}"
    echo -e "  Status:     $(format_status ${RDS_STATUS})"

    RDS_ENGINE=$(aws rds describe-db-instances \
        --region "$REGION" \
        --db-instance-identifier "$RDS_ID" \
        --query "DBInstances[0].Engine" \
        --output text 2>/dev/null)
    RDS_VERSION=$(aws rds describe-db-instances \
        --region "$REGION" \
        --db-instance-identifier "$RDS_ID" \
        --query "DBInstances[0].EngineVersion" \
        --output text 2>/dev/null)
    echo -e "  Engine:     ${GREEN}${RDS_ENGINE} ${RDS_VERSION}${NC}"

    RDS_SIZE=$(aws rds describe-db-instances \
        --region "$REGION" \
        --db-instance-identifier "$RDS_ID" \
        --query "DBInstances[0].AllocatedStorage" \
        --output text 2>/dev/null)
    echo -e "  Storage:    ${GREEN}${RDS_SIZE} GB${NC}"
else
    echo -e "  ${RED}Not found${NC}"
fi
echo ""

# Check ElastiCache
echo -e "${BLUE}[4/12] ElastiCache Redis${NC}"
REDIS_ID="gympt-${ENV}-redis"
REDIS_STATUS=$(aws elasticache describe-cache-clusters \
    --region "$REGION" \
    --cache-cluster-id "$REDIS_ID" \
    --query "CacheClusters[0].CacheClusterStatus" \
    --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$REDIS_STATUS" != "NOT_FOUND" ]; then
    echo -e "  Cluster:    ${GREEN}${REDIS_ID}${NC}"
    echo -e "  Status:     $(format_status ${REDIS_STATUS})"

    REDIS_NODES=$(aws elasticache describe-cache-clusters \
        --region "$REGION" \
        --cache-cluster-id "$REDIS_ID" \
        --query "CacheClusters[0].NumCacheNodes" \
        --output text 2>/dev/null)
    echo -e "  Nodes:      ${GREEN}${REDIS_NODES}${NC}"
else
    echo -e "  ${RED}Not found${NC}"
fi
echo ""

# Check DynamoDB
echo -e "${BLUE}[5/12] DynamoDB Tables${NC}"
DYNAMO_TABLES=$(aws dynamodb list-tables \
    --region "$REGION" \
    --query "TableNames[?contains(@, 'gympt-${ENV}')]" \
    --output text 2>/dev/null)

if [ -n "$DYNAMO_TABLES" ]; then
    TABLE_COUNT=$(echo "$DYNAMO_TABLES" | wc -w)
    echo -e "  Tables:     ${GREEN}${TABLE_COUNT}${NC}"
    for table in $DYNAMO_TABLES; do
        STATUS=$(aws dynamodb describe-table \
            --region "$REGION" \
            --table-name "$table" \
            --query "Table.TableStatus" \
            --output text 2>/dev/null)
        echo -e "    - ${table}: $(format_status ${STATUS})"
    done
else
    echo -e "  ${YELLOW}No tables found${NC}"
fi
echo ""

# Check S3 Buckets
echo -e "${BLUE}[6/12] S3 Buckets${NC}"
S3_BUCKETS=$(aws s3api list-buckets \
    --region "$REGION" \
    --query "Buckets[?contains(Name, 'gympt-${ENV}')].Name" \
    --output text 2>/dev/null)

if [ -n "$S3_BUCKETS" ]; then
    BUCKET_COUNT=$(echo "$S3_BUCKETS" | wc -w)
    echo -e "  Buckets:    ${GREEN}${BUCKET_COUNT}${NC}"
    for bucket in $S3_BUCKETS; do
        SIZE=$(aws s3 ls "s3://${bucket}" --recursive --summarize 2>/dev/null | grep "Total Size" | awk '{print $3}' || echo "0")
        SIZE_GB=$(echo "scale=2; $SIZE / 1024 / 1024 / 1024" | bc 2>/dev/null || echo "0")
        echo -e "    - ${bucket}: ${GREEN}${SIZE_GB} GB${NC}"
    done
else
    echo -e "  ${YELLOW}No buckets found${NC}"
fi
echo ""

# Check ECR Repositories
echo -e "${BLUE}[7/12] ECR Repositories${NC}"
ECR_REPOS=$(aws ecr describe-repositories \
    --region "$REGION" \
    --query "repositories[?contains(repositoryName, 'gympt')].repositoryName" \
    --output text 2>/dev/null)

if [ -n "$ECR_REPOS" ]; then
    REPO_COUNT=$(echo "$ECR_REPOS" | wc -w)
    echo -e "  Repos:      ${GREEN}${REPO_COUNT}${NC}"
    for repo in $ECR_REPOS; do
        IMAGE_COUNT=$(aws ecr describe-images \
            --region "$REGION" \
            --repository-name "$repo" \
            --query "length(imageDetails)" \
            --output text 2>/dev/null || echo "0")
        echo -e "    - ${repo}: ${GREEN}${IMAGE_COUNT} images${NC}"
    done
else
    echo -e "  ${YELLOW}No repositories found${NC}"
fi
echo ""

# Check SQS Queues
echo -e "${BLUE}[8/12] SQS Queues${NC}"
SQS_QUEUES=$(aws sqs list-queues \
    --region "$REGION" \
    --queue-name-prefix "gympt-${ENV}" \
    --query "QueueUrls" \
    --output text 2>/dev/null)

if [ -n "$SQS_QUEUES" ]; then
    QUEUE_COUNT=$(echo "$SQS_QUEUES" | wc -w)
    echo -e "  Queues:     ${GREEN}${QUEUE_COUNT}${NC}"
    for queue_url in $SQS_QUEUES; do
        queue_name=$(basename "$queue_url")
        MSG_COUNT=$(aws sqs get-queue-attributes \
            --region "$REGION" \
            --queue-url "$queue_url" \
            --attribute-names ApproximateNumberOfMessages \
            --query "Attributes.ApproximateNumberOfMessages" \
            --output text 2>/dev/null || echo "0")
        echo -e "    - ${queue_name}: ${GREEN}${MSG_COUNT} messages${NC}"
    done
else
    echo -e "  ${YELLOW}No queues found${NC}"
fi
echo ""

# Check KVS Streams
echo -e "${BLUE}[9/12] Kinesis Video Streams${NC}"
KVS_STREAMS=$(aws kinesisvideo list-streams \
    --region "$REGION" \
    --query "StreamInfoList[?contains(StreamName, 'gympt-${ENV}')].StreamName" \
    --output text 2>/dev/null)

if [ -n "$KVS_STREAMS" ]; then
    STREAM_COUNT=$(echo "$KVS_STREAMS" | wc -w)
    echo -e "  Streams:    ${GREEN}${STREAM_COUNT}${NC}"
    for stream in $KVS_STREAMS; do
        STATUS=$(aws kinesisvideo describe-stream \
            --region "$REGION" \
            --stream-name "$stream" \
            --query "StreamInfo.Status" \
            --output text 2>/dev/null)
        echo -e "    - ${stream}: $(format_status ${STATUS})"
    done
else
    echo -e "  ${YELLOW}No streams found${NC}"
fi
echo ""

# Check Lambda Functions
echo -e "${BLUE}[10/12] Lambda Functions${NC}"
LAMBDA_FUNCTIONS=$(aws lambda list-functions \
    --region "$REGION" \
    --query "Functions[?contains(FunctionName, 'gympt-${ENV}')].FunctionName" \
    --output text 2>/dev/null)

if [ -n "$LAMBDA_FUNCTIONS" ]; then
    FUNC_COUNT=$(echo "$LAMBDA_FUNCTIONS" | wc -w)
    echo -e "  Functions:  ${GREEN}${FUNC_COUNT}${NC}"
    for func in $LAMBDA_FUNCTIONS; do
        STATUS=$(aws lambda get-function \
            --region "$REGION" \
            --function-name "$func" \
            --query "Configuration.State" \
            --output text 2>/dev/null)
        echo -e "    - ${func}: $(format_status ${STATUS})"
    done
else
    echo -e "  ${YELLOW}No functions found${NC}"
fi
echo ""

# Check CloudFront Distributions
echo -e "${BLUE}[11/12] CloudFront Distributions${NC}"
CF_DISTROS=$(aws cloudfront list-distributions \
    --query "DistributionList.Items[?contains(Comment, 'gympt-${ENV}')].Id" \
    --output text 2>/dev/null)

if [ -n "$CF_DISTROS" ]; then
    DISTRO_COUNT=$(echo "$CF_DISTROS" | wc -w)
    echo -e "  Distros:    ${GREEN}${DISTRO_COUNT}${NC}"
    for distro in $CF_DISTROS; do
        STATUS=$(aws cloudfront get-distribution \
            --id "$distro" \
            --query "Distribution.Status" \
            --output text 2>/dev/null)
        echo -e "    - ${distro}: $(format_status ${STATUS})"
    done
else
    echo -e "  ${YELLOW}No distributions found${NC}"
fi
echo ""

# Check Cost
echo -e "${BLUE}[12/12] Estimated Monthly Cost${NC}"
START_DATE=$(date -d "1 month ago" +%Y-%m-%d)
END_DATE=$(date +%Y-%m-%d)

TOTAL_COST=$(aws ce get-cost-and-usage \
    --time-period Start=${START_DATE},End=${END_DATE} \
    --granularity MONTHLY \
    --metrics UnblendedCost \
    --filter file:/dev/stdin <<EOF 2>/dev/null || echo "0"
{
  "Tags": {
    "Key": "Environment",
    "Values": ["${ENV}"]
  }
}
EOF
)

if [ -n "$TOTAL_COST" ] && [ "$TOTAL_COST" != "0" ]; then
    COST_AMOUNT=$(echo "$TOTAL_COST" | grep -o '"Amount": "[^"]*' | head -1 | cut -d'"' -f4)
    COST_UNIT=$(echo "$TOTAL_COST" | grep -o '"Unit": "[^"]*' | head -1 | cut -d'"' -f4)
    echo -e "  Last Month: ${YELLOW}\$${COST_AMOUNT} ${COST_UNIT}${NC}"
else
    echo -e "  ${YELLOW}Cost data not available${NC}"
fi
echo ""

# Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Resource Check Complete${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Health Status Summary:${NC}"
echo -e "  ${GREEN}✓${NC} All critical services checked"
echo -e "  ${YELLOW}!${NC} Review any yellow/red statuses above"
echo ""
