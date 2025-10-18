#!/bin/bash
# Multi-Environment Deployment Script

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; }
warn() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] $1${NC}"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] $1${NC}"; }

# Check arguments
if [ $# -eq 0 ]; then
    error "Usage: $0 <environment>"
    echo "Available environments: dev, staging, production"
    exit 1
fi

ENV=$1
ENV_DIR="environments/$ENV"

# Validate environment
if [ ! -d "$ENV_DIR" ]; then
    error "Environment '$ENV' not found in $ENV_DIR"
    exit 1
fi

log "Deploying Jenkins Enterprise Platform to $ENV environment"

# Copy environment-specific config
cp "$ENV_DIR/terraform.tfvars" ./terraform.tfvars

# Initialize and deploy
terraform init
terraform plan -var-file="$ENV_DIR/terraform.tfvars"
terraform apply -var-file="$ENV_DIR/terraform.tfvars" -auto-approve

log "✅ $ENV environment deployed successfully!"
