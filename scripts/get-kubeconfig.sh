#!/bin/bash
# Get EKS kubeconfig and verify cluster access

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
ENV="${1:-dev}"
CLUSTER_NAME="gympt-${ENV}-cluster"
REGION="${AWS_REGION:-ap-northeast-2}"

# Usage information
if [ "$ENV" = "-h" ] || [ "$ENV" = "--help" ]; then
    echo "Usage: $0 [ENVIRONMENT]"
    echo ""
    echo "Arguments:"
    echo "  ENVIRONMENT    Environment name (default: dev)"
    echo ""
    echo "Examples:"
    echo "  $0              # Get dev kubeconfig"
    echo "  $0 prod         # Get prod kubeconfig"
    echo ""
    exit 0
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}EKS Kubeconfig Setup${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${YELLOW}Cluster:${NC}         ${GREEN}${CLUSTER_NAME}${NC}"
echo -e "${YELLOW}Region:${NC}          ${GREEN}${REGION}${NC}"
echo ""

# Verify AWS credentials
echo -e "${BLUE}[1/4]${NC} Verifying AWS credentials..."
if ! aws sts get-caller-identity &>/dev/null; then
    echo -e "${RED}Error: AWS credentials not configured${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} AWS credentials verified"

# Verify cluster exists
echo -e "${BLUE}[2/4]${NC} Checking cluster status..."
if ! aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${REGION}" &>/dev/null; then
    echo -e "${RED}Error: Cluster '${CLUSTER_NAME}' not found in region '${REGION}'${NC}"
    echo ""
    echo "Available clusters:"
    aws eks list-clusters --region "${REGION}" --output table
    exit 1
fi

CLUSTER_STATUS=$(aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${REGION}" --query 'cluster.status' --output text)
if [ "$CLUSTER_STATUS" != "ACTIVE" ]; then
    echo -e "${RED}Error: Cluster is not active (status: ${CLUSTER_STATUS})${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Cluster is active"

# Update kubeconfig
echo -e "${BLUE}[3/4]${NC} Updating kubeconfig..."
aws eks update-kubeconfig \
    --region "${REGION}" \
    --name "${CLUSTER_NAME}" \
    --alias "${CLUSTER_NAME}"

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to update kubeconfig${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Kubeconfig updated"

# Test connection
echo -e "${BLUE}[4/4]${NC} Testing cluster connection..."
echo ""

# Show cluster info
echo -e "${YELLOW}Cluster Information:${NC}"
kubectl cluster-info

echo ""
echo -e "${YELLOW}Kubernetes Version:${NC}"
kubectl version --short 2>/dev/null || kubectl version

echo ""
echo -e "${YELLOW}Nodes:${NC}"
kubectl get nodes -o wide

echo ""
echo -e "${YELLOW}System Pods:${NC}"
kubectl get pods -n kube-system

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Kubeconfig Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Current Context:${NC}"
kubectl config current-context

echo ""
echo -e "${BLUE}Useful Commands:${NC}"
echo -e "  View all contexts:       ${YELLOW}kubectl config get-contexts${NC}"
echo -e "  Switch context:          ${YELLOW}kubectl config use-context ${CLUSTER_NAME}${NC}"
echo -e "  Get namespaces:          ${YELLOW}kubectl get namespaces${NC}"
echo -e "  Get all resources:       ${YELLOW}kubectl get all -A${NC}"
echo ""
