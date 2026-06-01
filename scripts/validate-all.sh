#!/bin/bash
# Validate all Terraform modules and environments

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
TERRAFORM_ROOT="${PROJECT_ROOT}/terraform"

# Counters
TOTAL_MODULES=0
VALID_MODULES=0
FAILED_MODULES=0
TOTAL_ENVS=0
VALID_ENVS=0
FAILED_ENVS=0

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Terraform Validation${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if terraform is installed
if ! command -v terraform &> /dev/null; then
    echo -e "${RED}Error: Terraform is not installed${NC}"
    exit 1
fi

TERRAFORM_VERSION=$(terraform version -json | grep -o '"terraform_version": *"[^"]*' | cut -d'"' -f4)
echo -e "${YELLOW}Terraform Version:${NC} ${GREEN}${TERRAFORM_VERSION}${NC}"
echo ""

# Format check
echo -e "${BLUE}[1/3]${NC} Checking Terraform formatting..."
if terraform fmt -check -recursive "${TERRAFORM_ROOT}" > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} All files are properly formatted"
else
    echo -e "${YELLOW}!${NC} Some files need formatting"
    echo -e "${YELLOW}Run: terraform fmt -recursive ${TERRAFORM_ROOT}${NC}"
    echo ""
    echo "Files needing formatting:"
    terraform fmt -check -recursive "${TERRAFORM_ROOT}" 2>&1 | grep -v "^$" || true
fi
echo ""

# Validate modules
echo -e "${BLUE}[2/3]${NC} Validating Terraform modules..."
echo ""

if [ -d "${TERRAFORM_ROOT}/modules" ]; then
    for module_dir in "${TERRAFORM_ROOT}"/modules/*/; do
        if [ ! -d "$module_dir" ]; then
            continue
        fi

        module_name=$(basename "$module_dir")
        (( ++TOTAL_MODULES ))

        echo -ne "  ${YELLOW}${module_name}${NC} ... "

        cd "$module_dir"

        # Initialize without backend
        if ! terraform init -backend=false > /tmp/tf-init-${module_name}.log 2>&1; then
            echo -e "${RED}FAILED (init)${NC}"
            echo "    See: /tmp/tf-init-${module_name}.log"
            (( ++FAILED_MODULES ))
            continue
        fi

        # Validate
        if ! terraform validate > /tmp/tf-validate-${module_name}.log 2>&1; then
            echo -e "${RED}FAILED (validate)${NC}"
            echo "    See: /tmp/tf-validate-${module_name}.log"
            (( ++FAILED_MODULES ))
            continue
        fi

        echo -e "${GREEN}OK${NC}"
        (( ++VALID_MODULES ))
    done
fi

echo ""
echo -e "${YELLOW}Modules:${NC} ${GREEN}${VALID_MODULES}/${TOTAL_MODULES} passed${NC}"
if [ $FAILED_MODULES -gt 0 ]; then
    echo -e "${RED}Failed: ${FAILED_MODULES}${NC}"
fi
echo ""

# Validate environments
echo -e "${BLUE}[3/3]${NC} Validating Terraform environments..."
echo ""

if [ -d "${TERRAFORM_ROOT}/environments" ]; then
    for env_dir in "${TERRAFORM_ROOT}"/environments/*/; do
        if [ ! -d "$env_dir" ]; then
            continue
        fi

        env_name=$(basename "$env_dir")
        (( ++TOTAL_ENVS ))

        echo -ne "  ${YELLOW}${env_name}${NC} ... "

        cd "$env_dir"

        # Check for required files
        if [ ! -f "main.tf" ]; then
            echo -e "${RED}FAILED (no main.tf)${NC}"
            (( ++FAILED_ENVS ))
            continue
        fi

        # Initialize without backend
        if ! terraform init -backend=false > /tmp/tf-init-env-${env_name}.log 2>&1; then
            echo -e "${RED}FAILED (init)${NC}"
            echo "    See: /tmp/tf-init-env-${env_name}.log"
            (( ++FAILED_ENVS ))
            continue
        fi

        # Validate
        if ! terraform validate > /tmp/tf-validate-env-${env_name}.log 2>&1; then
            echo -e "${RED}FAILED (validate)${NC}"
            echo "    See: /tmp/tf-validate-env-${env_name}.log"
            (( ++FAILED_ENVS ))
            continue
        fi

        echo -e "${GREEN}OK${NC}"
        (( ++VALID_ENVS ))
    done
fi

echo ""
echo -e "${YELLOW}Environments:${NC} ${GREEN}${VALID_ENVS}/${TOTAL_ENVS} passed${NC}"
if [ $FAILED_ENVS -gt 0 ]; then
    echo -e "${RED}Failed: ${FAILED_ENVS}${NC}"
fi
echo ""

# Summary
TOTAL_FAILURES=$((FAILED_MODULES + FAILED_ENVS))

echo -e "${BLUE}========================================${NC}"
if [ $TOTAL_FAILURES -eq 0 ]; then
    echo -e "${GREEN}All Validations Passed!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${GREEN}✓${NC} Format check: passed"
    echo -e "${GREEN}✓${NC} Modules: ${VALID_MODULES}/${TOTAL_MODULES}"
    echo -e "${GREEN}✓${NC} Environments: ${VALID_ENVS}/${TOTAL_ENVS}"
    echo ""
    exit 0
else
    echo -e "${RED}Validation Failed${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""
    echo -e "${RED}✗${NC} Total failures: ${TOTAL_FAILURES}"
    if [ $FAILED_MODULES -gt 0 ]; then
        echo -e "${RED}✗${NC} Failed modules: ${FAILED_MODULES}"
    fi
    if [ $FAILED_ENVS -gt 0 ]; then
        echo -e "${RED}✗${NC} Failed environments: ${FAILED_ENVS}"
    fi
    echo ""
    echo -e "${YELLOW}Check log files in /tmp/tf-*.log for details${NC}"
    echo ""
    exit 1
fi
