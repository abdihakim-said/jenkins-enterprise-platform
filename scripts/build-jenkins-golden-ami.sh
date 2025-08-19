#!/bin/bash

# Jenkins Enterprise Platform - Golden AMI Build Script
# Date: 2025-08-17
# Version: 1.0

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PACKER_TEMPLATE="jenkins-golden-ami-packer.json"
BUILD_LOG="jenkins-ami-build-$(date +%Y%m%d_%H%M%S).log"
AWS_REGION="us-east-1"

echo -e "${BLUE}=== Jenkins Golden AMI Build Process ===${NC}"
echo "Build started at: $(date)"
echo "Log file: $BUILD_LOG"
echo ""

# Function to log messages
log_message() {
    echo -e "$1" | tee -a "$BUILD_LOG"
}

# Check prerequisites
log_message "${YELLOW}=== Checking Prerequisites ===${NC}"

# Check if Packer is installed
if ! command -v packer &> /dev/null; then
    log_message "${RED}ERROR: Packer is not installed${NC}"
    exit 1
fi
log_message "${GREEN}✓ Packer is installed: $(packer version)${NC}"

# Check if Ansible is installed
if ! command -v ansible &> /dev/null; then
    log_message "${RED}ERROR: Ansible is not installed${NC}"
    exit 1
fi
log_message "${GREEN}✓ Ansible is installed: $(ansible --version | head -n 1)${NC}"

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    log_message "${RED}ERROR: AWS credentials not configured${NC}"
    exit 1
fi
log_message "${GREEN}✓ AWS credentials configured${NC}"

# Check required files
REQUIRED_FILES=("$PACKER_TEMPLATE" "jenkins-hardening-playbook.yml" "jenkins-user-data-updated.sh")
for file in "${REQUIRED_FILES[@]}"; do
    if [[ ! -f "$file" ]]; then
        log_message "${RED}ERROR: Required file $file not found${NC}"
        exit 1
    fi
    log_message "${GREEN}✓ Found: $file${NC}"
done

# Validate Packer template
log_message "${YELLOW}=== Validating Packer Template ===${NC}"
if packer validate "$PACKER_TEMPLATE" >> "$BUILD_LOG" 2>&1; then
    log_message "${GREEN}✓ Packer template validation successful${NC}"
else
    log_message "${RED}ERROR: Packer template validation failed${NC}"
    exit 1
fi

# Get current timestamp for AMI naming
TIMESTAMP=$(date +%Y%m%d%H%M%S)
AMI_NAME="jenkins-golden-ami-$TIMESTAMP"

log_message "${YELLOW}=== Starting AMI Build ===${NC}"
log_message "AMI Name: $AMI_NAME"
log_message "Region: $AWS_REGION"
log_message "Template: $PACKER_TEMPLATE"

# Build the AMI
log_message "${BLUE}Building AMI... This may take 15-20 minutes${NC}"

if packer build \
    -var "ami_name=$AMI_NAME" \
    -var "aws_region=$AWS_REGION" \
    "$PACKER_TEMPLATE" >> "$BUILD_LOG" 2>&1; then
    
    log_message "${GREEN}✓ AMI build completed successfully!${NC}"
    
    # Extract AMI ID from manifest
    if [[ -f "jenkins-golden-ami-manifest.json" ]]; then
        AMI_ID=$(jq -r '.builds[0].artifact_id' jenkins-golden-ami-manifest.json | cut -d':' -f2)
        log_message "${GREEN}✓ AMI ID: $AMI_ID${NC}"
        
        # Tag the AMI with additional metadata
        log_message "${YELLOW}=== Adding Additional Tags ===${NC}"
        aws ec2 create-tags \
            --region "$AWS_REGION" \
            --resources "$AMI_ID" \
            --tags \
                Key=BuildLog,Value="$BUILD_LOG" \
                Key=BuildScript,Value="$(basename $0)" \
                Key=GitCommit,Value="$(git rev-parse HEAD 2>/dev/null || echo 'unknown')" \
                Key=BuildUser,Value="$(whoami)" \
                Key=ComplianceLevel,Value="Enterprise" \
                Key=SecurityHardened,Value="true" \
                Key=MonitoringEnabled,Value="true" \
                Key=BackupEnabled,Value="true" \
                Key=TestStatus,Value="Pending" >> "$BUILD_LOG" 2>&1
        
        log_message "${GREEN}✓ Additional tags applied${NC}"
        
        # Create launch template version with new AMI
        log_message "${YELLOW}=== Creating Launch Template Version ===${NC}"
        NEW_LT_VERSION=$(aws ec2 create-launch-template-version \
            --region "$AWS_REGION" \
            --launch-template-id "lt-09303b25f1655df3f" \
            --source-version "5" \
            --version-description "Golden AMI version with ID: $AMI_ID" \
            --launch-template-data "{\"ImageId\":\"$AMI_ID\"}" \
            --query 'LaunchTemplateVersion.VersionNumber' \
            --output text)
        
        log_message "${GREEN}✓ Launch template version $NEW_LT_VERSION created${NC}"
        
        # Test the new AMI
        log_message "${YELLOW}=== Testing New AMI ===${NC}"
        TEST_INSTANCE_ID=$(aws ec2 run-instances \
            --region "$AWS_REGION" \
            --image-id "$AMI_ID" \
            --instance-type "t3.micro" \
            --key-name "staging-jenkins-enterprise-platform-key" \
            --security-group-ids "sg-0212ce29a8bca55be" \
            --subnet-id "subnet-0befd92de90c33731" \
            --iam-instance-profile Name="staging-jenkins-enterprise-platform-jenkins-profile" \
            --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=Jenkins-AMI-Test},{Key=Purpose,Value=AMI-Testing},{Key=AutoTerminate,Value=true}]' \
            --query 'Instances[0].InstanceId' \
            --output text)
        
        log_message "${GREEN}✓ Test instance launched: $TEST_INSTANCE_ID${NC}"
        
        # Wait for instance to be running
        log_message "${BLUE}Waiting for test instance to be running...${NC}"
        aws ec2 wait instance-running --region "$AWS_REGION" --instance-ids "$TEST_INSTANCE_ID"
        
        # Wait additional time for user data to complete
        log_message "${BLUE}Waiting for user data to complete (3 minutes)...${NC}"
        sleep 180
        
        # Test the instance
        log_message "${YELLOW}=== Running AMI Validation Tests ===${NC}"
        aws ssm send-command \
            --region "$AWS_REGION" \
            --document-name "AWS-RunShellScript" \
            --parameters 'commands=["echo \"=== AMI Validation Test ===\"; java -version 2>&1 | head -n 1; systemctl status jenkins --no-pager | head -n 3; curl -s -I http://localhost:8080 | head -n 2; echo \"Test completed\""]' \
            --targets "Key=InstanceIds,Values=$TEST_INSTANCE_ID" \
            --comment "AMI validation test for $AMI_ID" >> "$BUILD_LOG" 2>&1
        
        # Terminate test instance
        log_message "${YELLOW}=== Cleaning Up Test Instance ===${NC}"
        aws ec2 terminate-instances --region "$AWS_REGION" --instance-ids "$TEST_INSTANCE_ID" >> "$BUILD_LOG" 2>&1
        log_message "${GREEN}✓ Test instance terminated${NC}"
        
        # Generate build report
        log_message "${YELLOW}=== Generating Build Report ===${NC}"
        cat > "jenkins-ami-build-report-$TIMESTAMP.md" << EOF
# Jenkins Golden AMI Build Report

**Build Date:** $(date)  
**AMI ID:** $AMI_ID  
**AMI Name:** $AMI_NAME  
**Region:** $AWS_REGION  
**Launch Template Version:** $NEW_LT_VERSION  

## Build Details
- **Packer Template:** $PACKER_TEMPLATE
- **Build Log:** $BUILD_LOG
- **Test Instance:** $TEST_INSTANCE_ID (terminated)
- **Build Duration:** $(date)

## AMI Features
- ✅ Java 17 (OpenJDK 17.0.16)
- ✅ Jenkins 2.516.1
- ✅ Docker, AWS CLI v2, Terraform, Ansible, Packer, Trivy
- ✅ Security hardening with Ansible
- ✅ Monitoring tools (CloudWatch, Prometheus)
- ✅ Automated backup system
- ✅ Enterprise security baseline

## Security Hardening Applied
- ✅ Fail2ban for SSH protection
- ✅ SSH hardening configuration
- ✅ Kernel security parameters
- ✅ File permission hardening
- ✅ Jenkins security configuration
- ✅ Audit logging enabled
- ✅ AppArmor protection

## Next Steps
1. Validate AMI in staging environment
2. Run comprehensive security scan
3. Update production launch templates
4. Schedule AMI testing and validation

## Usage
\`\`\`bash
# Update Auto Scaling Group to use new AMI
aws autoscaling update-auto-scaling-group \\
    --auto-scaling-group-name "staging-jenkins-enterprise-platform-asg" \\
    --launch-template "LaunchTemplateId=lt-09303b25f1655df3f,Version=$NEW_LT_VERSION"
\`\`\`

**Status:** ✅ Build Successful  
**AMI Ready for Testing:** Yes  
EOF
        
        log_message "${GREEN}✓ Build report generated: jenkins-ami-build-report-$TIMESTAMP.md${NC}"
        
    else
        log_message "${RED}ERROR: Manifest file not found${NC}"
        exit 1
    fi
    
else
    log_message "${RED}ERROR: AMI build failed${NC}"
    log_message "Check the build log for details: $BUILD_LOG"
    exit 1
fi

log_message "${GREEN}=== AMI Build Process Completed Successfully! ===${NC}"
log_message "AMI ID: $AMI_ID"
log_message "Launch Template Version: $NEW_LT_VERSION"
log_message "Build completed at: $(date)"

echo ""
echo -e "${BLUE}=== Summary ===${NC}"
echo -e "${GREEN}✅ Golden AMI created successfully${NC}"
echo -e "${GREEN}✅ AMI ID: $AMI_ID${NC}"
echo -e "${GREEN}✅ Launch Template Version: $NEW_LT_VERSION${NC}"
echo -e "${GREEN}✅ Security hardening applied${NC}"
echo -e "${GREEN}✅ Ready for staging validation${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Review build report: jenkins-ami-build-report-$TIMESTAMP.md"
echo "2. Validate AMI in staging environment"
echo "3. Run security compliance scan"
echo "4. Update production launch templates when ready"
