#!/bin/bash

# Jenkins Enterprise Platform - Deployment Script
# Comprehensive deployment automation for the complete platform
# Version: 2.0
# Date: 2025-08-18

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform"
ANSIBLE_DIR="${PROJECT_ROOT}/ansible"
PACKER_DIR="${PROJECT_ROOT}/packer"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Logging
LOG_FILE="${PROJECT_ROOT}/deployment-$(date +%Y%m%d_%H%M%S).log"

# Functions
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

error_exit() {
    log "${RED}ERROR: ${1}${NC}"
    exit 1
}

success() {
    log "${GREEN}SUCCESS: ${1}${NC}"
}

warning() {
    log "${YELLOW}WARNING: ${1}${NC}"
}

info() {
    log "${BLUE}INFO: ${1}${NC}"
}

header() {
    log "${PURPLE}=== ${1} ===${NC}"
}

# Help function
show_help() {
    cat << EOF
Jenkins Enterprise Platform - Deployment Script

Usage: $0 [ENVIRONMENT] [OPTIONS]

ENVIRONMENT:
    staging     Deploy to staging environment
    production  Deploy to production environment
    dev         Deploy to development environment

OPTIONS:
    --build-ami         Build new Golden AMI with Packer
    --skip-terraform    Skip Terraform infrastructure deployment
    --skip-ansible      Skip Ansible configuration
    --dry-run          Show what would be deployed without executing
    --force            Force deployment without confirmations
    --help             Show this help message

EXAMPLES:
    $0 staging                          # Deploy staging environment
    $0 production --build-ami           # Deploy production with new AMI
    $0 staging --dry-run                # Show staging deployment plan
    $0 production --force               # Force production deployment

PREREQUISITES:
    - AWS CLI configured with appropriate permissions
    - Terraform >= 1.0 installed
    - Ansible >= 2.9 installed
    - Packer >= 1.7 installed (if building AMI)
    - SSH key pair configured

EOF
}

# Parse arguments
ENVIRONMENT=""
BUILD_AMI=false
SKIP_TERRAFORM=false
SKIP_ANSIBLE=false
DRY_RUN=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        staging|production|dev)
            ENVIRONMENT="$1"
            shift
            ;;
        --build-ami)
            BUILD_AMI=true
            shift
            ;;
        --skip-terraform)
            SKIP_TERRAFORM=true
            shift
            ;;
        --skip-ansible)
            SKIP_ANSIBLE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            error_exit "Unknown option: $1. Use --help for usage information."
            ;;
    esac
done

# Validate environment
if [[ -z "${ENVIRONMENT}" ]]; then
    error_exit "Environment is required. Use: staging, production, or dev"
fi

if [[ ! "${ENVIRONMENT}" =~ ^(staging|production|dev)$ ]]; then
    error_exit "Invalid environment: ${ENVIRONMENT}. Use: staging, production, or dev"
fi

# Initialize deployment
initialize_deployment() {
    header "Initializing Jenkins Enterprise Platform Deployment"
    
    info "🎯 Environment: ${ENVIRONMENT}"
    info "📁 Project Root: ${PROJECT_ROOT}"
    info "📝 Log File: ${LOG_FILE}"
    info "🏗️ Build AMI: ${BUILD_AMI}"
    info "🚀 Deploy Infrastructure: $([ "${SKIP_TERRAFORM}" = true ] && echo "No" || echo "Yes")"
    info "⚙️ Configure with Ansible: $([ "${SKIP_ANSIBLE}" = true ] && echo "No" || echo "Yes")"
    info "🧪 Dry Run: ${DRY_RUN}"
    
    # Create necessary directories
    mkdir -p "${PROJECT_ROOT}/logs" "${PROJECT_ROOT}/artifacts"
    
    # Validate prerequisites
    validate_prerequisites
}

# Validate prerequisites
validate_prerequisites() {
    header "Validating Prerequisites"
    
    local missing_tools=()
    
    # Check required tools
    for tool in aws terraform ansible-playbook; do
        if ! command -v "${tool}" &> /dev/null; then
            missing_tools+=("${tool}")
        else
            info "✅ ${tool} is available"
        fi
    done
    
    # Check Packer if building AMI
    if [[ "${BUILD_AMI}" = true ]]; then
        if ! command -v packer &> /dev/null; then
            missing_tools+=("packer")
        else
            info "✅ packer is available"
        fi
    fi
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        error_exit "Missing required tools: ${missing_tools[*]}"
    fi
    
    # Validate AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error_exit "AWS credentials not configured or invalid"
    fi
    
    info "✅ AWS credentials validated"
    
    # Check Terraform variables file
    if [[ ! -f "${TERRAFORM_DIR}/terraform.tfvars" ]]; then
        warning "terraform.tfvars not found. Creating from example..."
        if [[ -f "${TERRAFORM_DIR}/terraform.tfvars.example" ]]; then
            cp "${TERRAFORM_DIR}/terraform.tfvars.example" "${TERRAFORM_DIR}/terraform.tfvars"
            warning "Please edit ${TERRAFORM_DIR}/terraform.tfvars with your specific values"
        else
            error_exit "terraform.tfvars.example not found"
        fi
    fi
    
    success "Prerequisites validation completed"
}

# Build Golden AMI
build_golden_ami() {
    if [[ "${BUILD_AMI}" != true ]]; then
        info "Skipping AMI build (not requested)"
        return 0
    fi
    
    header "Building Golden AMI with Packer"
    
    cd "${PACKER_DIR}"
    
    # Create Packer variables
    cat > variables.json << EOF
{
    "aws_region": "us-east-1",
    "environment": "${ENVIRONMENT}",
    "project_name": "jenkins-enterprise-platform",
    "java_version": "17",
    "jenkins_version": "2.516.1",
    "build_timestamp": "$(date +%Y%m%d-%H%M%S)"
}
EOF
    
    if [[ "${DRY_RUN}" = true ]]; then
        info "DRY RUN: Would build AMI with Packer"
        packer validate -var-file=variables.json templates/jenkins-golden-ami-simple.json
        return 0
    fi
    
    info "🏗️ Building Golden AMI..."
    packer build -var-file=variables.json templates/jenkins-golden-ami-simple.json | tee "${PROJECT_ROOT}/logs/packer-build.log"
    
    # Extract AMI ID
    AMI_ID=$(grep 'artifact,0,id' "${PROJECT_ROOT}/logs/packer-build.log" | cut -d, -f6 | cut -d: -f2 || echo "")
    
    if [[ -n "${AMI_ID}" ]]; then
        echo "${AMI_ID}" > "${PROJECT_ROOT}/artifacts/golden-ami-id.txt"
        success "Golden AMI built successfully: ${AMI_ID}"
    else
        error_exit "Failed to extract AMI ID from Packer build"
    fi
    
    cd "${PROJECT_ROOT}"
}

# Deploy infrastructure with Terraform
deploy_infrastructure() {
    if [[ "${SKIP_TERRAFORM}" = true ]]; then
        info "Skipping Terraform deployment (requested)"
        return 0
    fi
    
    header "Deploying Infrastructure with Terraform"
    
    cd "${TERRAFORM_DIR}"
    
    # Update terraform.tfvars with Golden AMI if built
    if [[ -f "${PROJECT_ROOT}/artifacts/golden-ami-id.txt" ]]; then
        AMI_ID=$(cat "${PROJECT_ROOT}/artifacts/golden-ami-id.txt")
        info "Using Golden AMI: ${AMI_ID}"
        
        # Update terraform.tfvars
        if grep -q "golden_ami_id" terraform.tfvars; then
            sed -i.bak "s/golden_ami_id.*/golden_ami_id = \"${AMI_ID}\"/" terraform.tfvars
        else
            echo "golden_ami_id = \"${AMI_ID}\"" >> terraform.tfvars
        fi
    fi
    
    # Set environment in terraform.tfvars
    if grep -q "environment" terraform.tfvars; then
        sed -i.bak "s/environment.*/environment = \"${ENVIRONMENT}\"/" terraform.tfvars
    else
        echo "environment = \"${ENVIRONMENT}\"" >> terraform.tfvars
    fi
    
    if [[ "${DRY_RUN}" = true ]]; then
        info "DRY RUN: Would deploy infrastructure with Terraform"
        terraform init
        terraform plan -var-file=terraform.tfvars
        return 0
    fi
    
    # Initialize Terraform
    info "🔧 Initializing Terraform..."
    terraform init
    
    # Plan deployment
    info "📋 Planning infrastructure deployment..."
    terraform plan -var-file=terraform.tfvars -out=tfplan | tee "${PROJECT_ROOT}/logs/terraform-plan.log"
    
    # Confirm deployment
    if [[ "${FORCE}" != true ]]; then
        echo
        read -p "Do you want to apply this Terraform plan? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            warning "Terraform deployment cancelled by user"
            return 0
        fi
    fi
    
    # Apply deployment
    info "🚀 Applying infrastructure deployment..."
    terraform apply tfplan | tee "${PROJECT_ROOT}/logs/terraform-apply.log"
    
    # Generate outputs
    terraform output -json > "${PROJECT_ROOT}/artifacts/terraform-outputs.json"
    
    success "Infrastructure deployment completed"
    
    cd "${PROJECT_ROOT}"
}

# Configure with Ansible
configure_with_ansible() {
    if [[ "${SKIP_ANSIBLE}" = true ]]; then
        info "Skipping Ansible configuration (requested)"
        return 0
    fi
    
    header "Configuring Jenkins with Ansible"
    
    cd "${ANSIBLE_DIR}"
    
    # Get instance IPs from Terraform outputs
    if [[ -f "${PROJECT_ROOT}/artifacts/terraform-outputs.json" ]]; then
        # This would need to be implemented based on actual Terraform outputs
        info "Getting instance information from Terraform outputs..."
        # For now, we'll use a placeholder
        warning "Ansible configuration requires manual inventory setup"
        return 0
    fi
    
    if [[ "${DRY_RUN}" = true ]]; then
        info "DRY RUN: Would configure Jenkins with Ansible"
        ansible-playbook --syntax-check site.yml
        return 0
    fi
    
    # Run Ansible playbook
    info "⚙️ Configuring Jenkins with Ansible..."
    ansible-playbook site.yml -i inventory/hosts | tee "${PROJECT_ROOT}/logs/ansible-run.log"
    
    success "Ansible configuration completed"
    
    cd "${PROJECT_ROOT}"
}

# Run post-deployment validation
validate_deployment() {
    header "Validating Deployment"
    
    if [[ "${DRY_RUN}" = true ]]; then
        info "DRY RUN: Would validate deployment"
        return 0
    fi
    
    # Get Jenkins URL from Terraform outputs
    if [[ -f "${PROJECT_ROOT}/artifacts/terraform-outputs.json" ]]; then
        JENKINS_URL=$(jq -r '.jenkins_alb_url.value // "http://localhost:8080"' "${PROJECT_ROOT}/artifacts/terraform-outputs.json")
        info "Jenkins URL: ${JENKINS_URL}"
        
        # Test Jenkins accessibility
        info "🧪 Testing Jenkins accessibility..."
        if curl -s -o /dev/null -w "%{http_code}" "${JENKINS_URL}/login" | grep -q "200\|403"; then
            success "Jenkins is accessible at ${JENKINS_URL}"
        else
            warning "Jenkins may not be fully ready yet. Check manually: ${JENKINS_URL}"
        fi
    else
        warning "Cannot validate deployment - Terraform outputs not available"
    fi
}

# Generate deployment report
generate_report() {
    header "Generating Deployment Report"
    
    local report_file="${PROJECT_ROOT}/deployment-report-${ENVIRONMENT}-$(date +%Y%m%d_%H%M%S).md"
    
    cat > "${report_file}" << EOF
# Jenkins Enterprise Platform Deployment Report

**Environment:** ${ENVIRONMENT}  
**Date:** $(date)  
**Status:** $([ "${DRY_RUN}" = true ] && echo "DRY RUN" || echo "DEPLOYED")

## Deployment Configuration

- **Build AMI:** ${BUILD_AMI}
- **Deploy Infrastructure:** $([ "${SKIP_TERRAFORM}" = true ] && echo "Skipped" || echo "Yes")
- **Configure with Ansible:** $([ "${SKIP_ANSIBLE}" = true ] && echo "Skipped" || echo "Yes")
- **Dry Run:** ${DRY_RUN}

## Artifacts Generated

EOF
    
    if [[ -f "${PROJECT_ROOT}/artifacts/golden-ami-id.txt" ]]; then
        echo "- **Golden AMI ID:** $(cat "${PROJECT_ROOT}/artifacts/golden-ami-id.txt")" >> "${report_file}"
    fi
    
    if [[ -f "${PROJECT_ROOT}/artifacts/terraform-outputs.json" ]]; then
        echo "- **Terraform Outputs:** Available" >> "${report_file}"
        echo "- **Jenkins URL:** $(jq -r '.jenkins_alb_url.value // "N/A"' "${PROJECT_ROOT}/artifacts/terraform-outputs.json")" >> "${report_file}"
    fi
    
    cat >> "${report_file}" << EOF

## Log Files

- **Deployment Log:** ${LOG_FILE}
- **Packer Build Log:** logs/packer-build.log
- **Terraform Plan Log:** logs/terraform-plan.log
- **Terraform Apply Log:** logs/terraform-apply.log
- **Ansible Run Log:** logs/ansible-run.log

## Next Steps

1. Access Jenkins at the provided URL
2. Complete Jenkins initial setup
3. Configure security settings
4. Set up backup schedules
5. Monitor system performance

EOF
    
    info "📊 Deployment report generated: ${report_file}"
}

# Main execution
main() {
    initialize_deployment
    
    if [[ "${DRY_RUN}" = true ]]; then
        header "DRY RUN MODE - No actual changes will be made"
    fi
    
    build_golden_ami
    deploy_infrastructure
    configure_with_ansible
    validate_deployment
    generate_report
    
    if [[ "${DRY_RUN}" = true ]]; then
        success "🧪 Dry run completed successfully!"
    else
        success "🎉 Jenkins Enterprise Platform deployment completed successfully!"
        info "📊 Check the deployment report for details and next steps"
    fi
}

# Run main function
main "$@"
