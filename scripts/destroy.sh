#!/bin/bash
# =========================================
# Infrastructure Destruction Script
# =========================================
# This script safely destroys all AWS resources created by Terraform

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $*"
}

warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*"
}

# Locate terraform directory so the script can be run from scripts/ or terraform/
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TF_DIR="${ROOT_DIR}/terraform"

if [ -f "${TF_DIR}/main.tf" ]; then
    cd "${TF_DIR}"
elif [ -f "main.tf" ]; then
    # already in terraform directory
    :
else
    error "Cannot locate terraform directory with main.tf. Please run from repo root/scripts or terraform directory."
    exit 1
fi

log "Starting infrastructure destruction process..."

# Show what will be destroyed
log "Showing what will be destroyed..."
terraform plan -destroy

# Confirm destruction
echo
warning "This will PERMANENTLY DESTROY all AWS resources!"
warning "This action cannot be undone!"
echo
read -p "Are you absolutely sure you want to destroy all resources? (type 'yes' to confirm): " confirm

if [ "$confirm" != "yes" ]; then
    log "Destruction cancelled by user"
    exit 0
fi

# Additional confirmation for production
if grep -q 'environment.*=.*"prod"' terraform.tfvars 2>/dev/null; then
    warning "PRODUCTION environment detected!"
    echo
    read -p "Type the project name to confirm production destruction: " project_confirm

    PROJECT_NAME=$(grep 'project_name' terraform.tfvars | cut -d'"' -f2)
    if [ "$project_confirm" != "$PROJECT_NAME" ]; then
        error "Project name confirmation failed. Aborting destruction."
        exit 1
    fi
fi

log "Starting destruction process..."

# Destroy in reverse order to avoid dependency issues
log "Destroying EC2 instances and associated resources..."
terraform destroy -target=aws_instance.main -auto-approve || true

log "Destroying launch template..."
terraform destroy -target=aws_launch_template.main -auto-approve || true

log "Destroying Systems Manager resources..."
terraform destroy -target=aws_ssm_maintenance_window_task.install_patches -auto-approve || true
terraform destroy -target=aws_ssm_maintenance_window_target.main -auto-approve || true
terraform destroy -target=aws_ssm_maintenance_window.main -auto-approve || true
terraform destroy -target=aws_ssm_patch_baseline.amazon_linux -auto-approve || true

log "Destroying VPC endpoints..."
terraform destroy -target=aws_vpc_endpoint.ssm -auto-approve || true
terraform destroy -target=aws_vpc_endpoint.ssm_messages -auto-approve || true
terraform destroy -target=aws_vpc_endpoint.ec2_messages -auto-approve || true

log "Destroying NAT Gateway and Elastic IP..."
terraform destroy -target=aws_nat_gateway.main -auto-approve || true
terraform destroy -target=aws_eip.nat -auto-approve || true

log "Destroying remaining resources..."
terraform destroy -auto-approve

# Verify destruction
log "Verifying all resources are destroyed..."
if terraform show | grep -q "No state"; then
    log "All resources successfully destroyed!"
else
    warning "Some resources may still exist. Please check manually."
    terraform show
fi

# Clean up Terraform files
read -p "Do you want to clean up Terraform state files? (y/n): " cleanup
if [ "$cleanup" = "y" ]; then
    log "Cleaning up Terraform files..."
    rm -f terraform.tfstate*
    rm -f tfplan
    log "Terraform state files cleaned up"
fi

log "Infrastructure destruction completed!"
