#!/bin/bash
# Jenkins Enterprise Platform Deployment Script
# This script will deploy the complete platform step by step

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

log_warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

log_info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

echo "=========================================="
echo "🚀 Jenkins Enterprise Platform Deployment"
echo "=========================================="
echo ""

# Step 1: Pre-deployment checks
log "Step 1: Running pre-deployment checks..."

# Check if AWS CLI is configured
if ! aws sts get-caller-identity &> /dev/null; then
    log_error "AWS CLI is not configured. Please run 'aws configure' first."
    exit 1
fi

# Check if Terraform is installed
if ! command -v terraform &> /dev/null; then
    log_error "Terraform is not installed. Please install Terraform first."
    exit 1
fi

# Display AWS account info
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region)
log_info "AWS Account: ${AWS_ACCOUNT}"
log_info "AWS Region: ${AWS_REGION}"

# Step 2: Initialize Terraform
log "Step 2: Initializing Terraform..."
terraform init

if [ $? -eq 0 ]; then
    log "✅ Terraform initialized successfully"
else
    log_error "❌ Terraform initialization failed"
    exit 1
fi

# Step 3: Validate Terraform configuration
log "Step 3: Validating Terraform configuration..."
terraform validate

if [ $? -eq 0 ]; then
    log "✅ Terraform configuration is valid"
else
    log_error "❌ Terraform configuration validation failed"
    exit 1
fi

# Step 4: Plan deployment
log "Step 4: Planning deployment..."
terraform plan -out=tfplan

if [ $? -eq 0 ]; then
    log "✅ Terraform plan completed successfully"
else
    log_error "❌ Terraform plan failed"
    exit 1
fi

# Step 5: Show what will be created
log "Step 5: Deployment summary..."
echo ""
echo "📋 Resources to be created:"
echo "- VPC with public/private subnets across 3 AZs"
echo "- Internet Gateway and NAT Gateway"
echo "- Security Groups for Jenkins, ALB, and EFS"
echo "- IAM roles and policies"
echo "- EFS file system with mount targets"
echo "- Application Load Balancer"
echo "- Auto Scaling Group with Launch Template"
echo "- CloudWatch dashboards, alarms, and log groups"
echo "- S3 bucket for backups with lifecycle policies"
echo "- Blue/Green deployment infrastructure"
echo ""

# Ask for confirmation
read -p "🤔 Do you want to proceed with deployment? (yes/no): " confirm
if [[ $confirm != "yes" ]]; then
    log_warn "Deployment cancelled by user"
    exit 0
fi

# Step 6: Apply Terraform
log "Step 6: Applying Terraform configuration..."
log_warn "This will take approximately 10-15 minutes..."

terraform apply tfplan

if [ $? -eq 0 ]; then
    log "✅ Terraform apply completed successfully"
else
    log_error "❌ Terraform apply failed"
    exit 1
fi

# Step 7: Wait for Jenkins to be ready
log "Step 7: Waiting for Jenkins to be ready..."
log_info "Jenkins startup takes 15-20 minutes on first boot..."

# Get Jenkins URL
JENKINS_URL=$(terraform output -raw jenkins_url 2>/dev/null || echo "")
if [ -n "$JENKINS_URL" ]; then
    log_info "Jenkins URL: $JENKINS_URL"
    
    # Wait for Jenkins to respond
    log_info "Checking Jenkins availability..."
    for i in {1..60}; do
        if curl -s --connect-timeout 5 "$JENKINS_URL" > /dev/null 2>&1; then
            log "✅ Jenkins is responding!"
            break
        else
            echo -n "."
            sleep 30
        fi
        
        if [ $i -eq 60 ]; then
            log_warn "Jenkins is taking longer than expected to start"
            log_info "You can monitor progress with: ./monitor-jenkins.sh"
        fi
    done
fi

# Step 8: Display deployment results
log "Step 8: Deployment completed! 🎉"
echo ""
echo "=========================================="
echo "🎉 DEPLOYMENT SUCCESSFUL!"
echo "=========================================="
echo ""

# Show outputs
log "📊 Deployment Information:"
terraform output

echo ""
log "🔧 Next Steps:"
echo "1. Access Jenkins at: $(terraform output -raw jenkins_url 2>/dev/null || echo 'Check terraform output')"
echo "2. Get admin password: aws ssm get-parameter --name '/jenkins/staging/admin-password' --with-decryption --query 'Parameter.Value' --output text"
echo "3. Monitor Jenkins: ./monitor-jenkins.sh"
echo "4. Check logs: aws logs tail /jenkins/staging/user-data --follow"
echo ""

log "✅ Jenkins Enterprise Platform deployed successfully!"
echo "📚 Check the learning guides in the docs/ folder to understand what was built."
echo ""
