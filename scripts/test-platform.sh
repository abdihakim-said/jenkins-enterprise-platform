#!/bin/bash

# Jenkins Enterprise Platform - Automated Testing Script
# Tests all platform components and generates report

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
ENVIRONMENT="${ENVIRONMENT:-dev}"
REGION="${AWS_REGION:-us-east-1}"
COMPONENT="${1:-all}"

# Counters
PASSED=0
FAILED=0
WARNINGS=0

# Functions
print_header() {
    echo -e "\n${YELLOW}========================================${NC}"
    echo -e "${YELLOW}$1${NC}"
    echo -e "${YELLOW}========================================${NC}\n"
}

test_pass() {
    echo -e "${GREEN}✓ PASS:${NC} $1"
    ((PASSED++))
}

test_fail() {
    echo -e "${RED}✗ FAIL:${NC} $1"
    ((FAILED++))
}

test_warn() {
    echo -e "${YELLOW}⚠ WARN:${NC} $1"
    ((WARNINGS++))
}

# Test VPC
test_vpc() {
    print_header "Testing VPC & Network"
    
    # VPC exists
    VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=tag:Environment,Values=$ENVIRONMENT" \
        --query 'Vpcs[0].VpcId' \
        --output text \
        --region $REGION 2>/dev/null)
    
    if [ "$VPC_ID" != "None" ] && [ -n "$VPC_ID" ]; then
        test_pass "VPC exists: $VPC_ID"
    else
        test_fail "VPC not found"
        return
    fi
    
    # Subnets
    SUBNET_COUNT=$(aws ec2 describe-subnets \
        --filters "Name=tag:Environment,Values=$ENVIRONMENT" \
        --query 'length(Subnets)' \
        --output text \
        --region $REGION)
    
    if [ "$SUBNET_COUNT" -ge 6 ]; then
        test_pass "Subnets configured: $SUBNET_COUNT subnets"
    else
        test_fail "Insufficient subnets: $SUBNET_COUNT (expected 6)"
    fi
    
    # NAT Gateway
    NAT_STATE=$(aws ec2 describe-nat-gateways \
        --filter "Name=tag:Environment,Values=$ENVIRONMENT" \
        --query 'NatGateways[0].State' \
        --output text \
        --region $REGION)
    
    if [ "$NAT_STATE" == "available" ]; then
        test_pass "NAT Gateway operational"
    else
        test_fail "NAT Gateway not available: $NAT_STATE"
    fi
    
    # Internet Gateway
    IGW_STATE=$(aws ec2 describe-internet-gateways \
        --filters "Name=tag:Environment,Values=$ENVIRONMENT" \
        --query 'InternetGateways[0].Attachments[0].State' \
        --output text \
        --region $REGION)
    
    if [ "$IGW_STATE" == "available" ]; then
        test_pass "Internet Gateway attached"
    else
        test_fail "Internet Gateway not attached: $IGW_STATE"
    fi
}

# Test Security Groups
test_security_groups() {
    print_header "Testing Security Groups"
    
    # ALB security group
    ALB_SG=$(aws ec2 describe-security-groups \
        --filters "Name=tag:Name,Values=*alb*" "Name=tag:Environment,Values=$ENVIRONMENT" \
        --query 'SecurityGroups[0].GroupId' \
        --output text \
        --region $REGION)
    
    if [ "$ALB_SG" != "None" ] && [ -n "$ALB_SG" ]; then
        test_pass "ALB security group exists: $ALB_SG"
    else
        test_fail "ALB security group not found"
    fi
    
    # Jenkins security group
    JENKINS_SG=$(aws ec2 describe-security-groups \
        --filters "Name=tag:Name,Values=*jenkins*" "Name=tag:Environment,Values=$ENVIRONMENT" \
        --query 'SecurityGroups[0].GroupId' \
        --output text \
        --region $REGION)
    
    if [ "$JENKINS_SG" != "None" ] && [ -n "$JENKINS_SG" ]; then
        test_pass "Jenkins security group exists: $JENKINS_SG"
    else
        test_fail "Jenkins security group not found"
    fi
    
    # EFS security group
    EFS_SG=$(aws ec2 describe-security-groups \
        --filters "Name=tag:Name,Values=*efs*" "Name=tag:Environment,Values=$ENVIRONMENT" \
        --query 'SecurityGroups[0].GroupId' \
        --output text \
        --region $REGION)
    
    if [ "$EFS_SG" != "None" ] && [ -n "$EFS_SG" ]; then
        test_pass "EFS security group exists: $EFS_SG"
    else
        test_fail "EFS security group not found"
    fi
}

# Test EFS
test_efs() {
    print_header "Testing EFS Storage"
    
    # EFS exists
    EFS_ID=$(aws efs describe-file-systems \
        --query "FileSystems[?Tags[?Key=='Environment' && Value=='$ENVIRONMENT']].FileSystemId" \
        --output text \
        --region $REGION)
    
    if [ -n "$EFS_ID" ]; then
        test_pass "EFS filesystem exists: $EFS_ID"
    else
        test_fail "EFS filesystem not found"
        return
    fi
    
    # Mount targets
    MOUNT_COUNT=$(aws efs describe-mount-targets \
        --file-system-id $EFS_ID \
        --query 'length(MountTargets)' \
        --output text \
        --region $REGION)
    
    if [ "$MOUNT_COUNT" -ge 3 ]; then
        test_pass "EFS mount targets: $MOUNT_COUNT"
    else
        test_warn "Limited mount targets: $MOUNT_COUNT (expected 3)"
    fi
    
    # Encryption
    ENCRYPTED=$(aws efs describe-file-systems \
        --file-system-id $EFS_ID \
        --query 'FileSystems[0].Encrypted' \
        --output text \
        --region $REGION)
    
    if [ "$ENCRYPTED" == "True" ]; then
        test_pass "EFS encryption enabled"
    else
        test_fail "EFS encryption not enabled"
    fi
}

# Test ALB
test_alb() {
    print_header "Testing Application Load Balancer"
    
    # ALB exists
    ALB_STATE=$(aws elbv2 describe-load-balancers \
        --names ${ENVIRONMENT}-jenkins-alb \
        --query 'LoadBalancers[0].State.Code' \
        --output text \
        --region $REGION 2>/dev/null)
    
    if [ "$ALB_STATE" == "active" ]; then
        test_pass "ALB is active"
    else
        test_fail "ALB not active: $ALB_STATE"
        return
    fi
    
    # Get ALB DNS
    ALB_DNS=$(aws elbv2 describe-load-balancers \
        --names ${ENVIRONMENT}-jenkins-alb \
        --query 'LoadBalancers[0].DNSName' \
        --output text \
        --region $REGION)
    
    # Target health
    TG_ARN=$(aws elbv2 describe-target-groups \
        --names ${ENVIRONMENT}-jenkins-tg \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text \
        --region $REGION 2>/dev/null)
    
    if [ -n "$TG_ARN" ]; then
        HEALTHY_COUNT=$(aws elbv2 describe-target-health \
            --target-group-arn $TG_ARN \
            --query "length(TargetHealthDescriptions[?TargetHealth.State=='healthy'])" \
            --output text \
            --region $REGION)
        
        if [ "$HEALTHY_COUNT" -gt 0 ]; then
            test_pass "Target group has $HEALTHY_COUNT healthy targets"
        else
            test_fail "No healthy targets in target group"
        fi
    fi
    
    # HTTP response
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://$ALB_DNS:8080 2>/dev/null || echo "000")
    
    if [ "$HTTP_CODE" == "200" ] || [ "$HTTP_CODE" == "403" ]; then
        test_pass "ALB responding: HTTP $HTTP_CODE"
    else
        test_fail "ALB not responding: HTTP $HTTP_CODE"
    fi
}

# Test Auto Scaling
test_autoscaling() {
    print_header "Testing Auto Scaling Groups"
    
    # Main ASG
    MAIN_ASG="${ENVIRONMENT}-jenkins-enterprise-platform-asg"
    MAIN_CAPACITY=$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names $MAIN_ASG \
        --query 'AutoScalingGroups[0].DesiredCapacity' \
        --output text \
        --region $REGION 2>/dev/null)
    
    if [ "$MAIN_CAPACITY" != "None" ] && [ -n "$MAIN_CAPACITY" ]; then
        test_pass "Main ASG configured: $MAIN_CAPACITY instances"
    else
        test_fail "Main ASG not found"
    fi
    
    # Blue ASG
    BLUE_ASG="jenkins-enterprise-platform-${ENVIRONMENT}-blue-asg"
    BLUE_CAPACITY=$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names $BLUE_ASG \
        --query 'AutoScalingGroups[0].DesiredCapacity' \
        --output text \
        --region $REGION 2>/dev/null)
    
    if [ "$BLUE_CAPACITY" != "None" ]; then
        test_pass "Blue ASG configured: $BLUE_CAPACITY instances"
    else
        test_warn "Blue ASG not found (may not be deployed)"
    fi
    
    # Green ASG
    GREEN_ASG="jenkins-enterprise-platform-${ENVIRONMENT}-green-asg"
    GREEN_CAPACITY=$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names $GREEN_ASG \
        --query 'AutoScalingGroups[0].DesiredCapacity' \
        --output text \
        --region $REGION 2>/dev/null)
    
    if [ "$GREEN_CAPACITY" != "None" ]; then
        test_pass "Green ASG configured: $GREEN_CAPACITY instances"
    else
        test_warn "Green ASG not found (may not be deployed)"
    fi
}

# Test Jenkins
test_jenkins() {
    print_header "Testing Jenkins Application"
    
    # Get ALB DNS
    ALB_DNS=$(aws elbv2 describe-load-balancers \
        --names ${ENVIRONMENT}-jenkins-alb \
        --query 'LoadBalancers[0].DNSName' \
        --output text \
        --region $REGION 2>/dev/null)
    
    if [ -z "$ALB_DNS" ]; then
        test_fail "Cannot get ALB DNS"
        return
    fi
    
    # Jenkins accessible
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://$ALB_DNS:8080 2>/dev/null || echo "000")
    
    if [ "$HTTP_CODE" == "200" ] || [ "$HTTP_CODE" == "403" ]; then
        test_pass "Jenkins accessible: HTTP $HTTP_CODE"
    else
        test_fail "Jenkins not accessible: HTTP $HTTP_CODE"
    fi
    
    # Jenkins version
    JENKINS_VERSION=$(curl -s http://$ALB_DNS:8080 2>/dev/null | grep -o "Jenkins ver. [0-9.]*" || echo "")
    
    if [ -n "$JENKINS_VERSION" ]; then
        test_pass "Jenkins version detected: $JENKINS_VERSION"
    else
        test_warn "Cannot detect Jenkins version"
    fi
    
    # Admin password in SSM
    ADMIN_PASS=$(aws ssm get-parameter \
        --name "/jenkins/${ENVIRONMENT}/admin-password" \
        --with-decryption \
        --query 'Parameter.Value' \
        --output text \
        --region $REGION 2>/dev/null)
    
    if [ -n "$ADMIN_PASS" ] && [ "$ADMIN_PASS" != "None" ]; then
        test_pass "Admin password stored in SSM"
    else
        test_warn "Admin password not found in SSM"
    fi
}

# Test Lambda
test_lambda() {
    print_header "Testing Lambda Blue-Green Orchestrator"
    
    LAMBDA_NAME="jenkins-enterprise-platform-${ENVIRONMENT}-deployment-orchestrator"
    
    # Lambda exists
    LAMBDA_STATE=$(aws lambda get-function \
        --function-name $LAMBDA_NAME \
        --query 'Configuration.State' \
        --output text \
        --region $REGION 2>/dev/null)
    
    if [ "$LAMBDA_STATE" == "Active" ]; then
        test_pass "Lambda function active"
    else
        test_warn "Lambda function not found or inactive"
        return
    fi
    
    # EventBridge rule
    RULE_STATE=$(aws events list-rules \
        --name-prefix jenkins-enterprise-platform-${ENVIRONMENT} \
        --query 'Rules[0].State' \
        --output text \
        --region $REGION 2>/dev/null)
    
    if [ "$RULE_STATE" == "ENABLED" ]; then
        test_pass "EventBridge rule enabled"
    else
        test_warn "EventBridge rule not enabled"
    fi
}

# Test CloudWatch
test_cloudwatch() {
    print_header "Testing CloudWatch Monitoring"
    
    # Dashboard
    DASHBOARD=$(aws cloudwatch list-dashboards \
        --query "DashboardEntries[?contains(DashboardName, '${ENVIRONMENT}-jenkins')].DashboardName" \
        --output text \
        --region $REGION)
    
    if [ -n "$DASHBOARD" ]; then
        test_pass "CloudWatch dashboard exists: $DASHBOARD"
    else
        test_warn "CloudWatch dashboard not found"
    fi
    
    # Alarms
    ALARM_COUNT=$(aws cloudwatch describe-alarms \
        --alarm-name-prefix ${ENVIRONMENT}-jenkins \
        --query 'length(MetricAlarms)' \
        --output text \
        --region $REGION)
    
    if [ "$ALARM_COUNT" -gt 0 ]; then
        test_pass "CloudWatch alarms configured: $ALARM_COUNT alarms"
    else
        test_warn "No CloudWatch alarms found"
    fi
    
    # Log groups
    LOG_COUNT=$(aws logs describe-log-groups \
        --log-group-name-prefix /jenkins/${ENVIRONMENT} \
        --query 'length(logGroups)' \
        --output text \
        --region $REGION)
    
    if [ "$LOG_COUNT" -gt 0 ]; then
        test_pass "Log groups configured: $LOG_COUNT groups"
    else
        test_warn "No log groups found"
    fi
}

# Test Security
test_security() {
    print_header "Testing Security & Compliance"
    
    # KMS key
    KMS_ALIAS=$(aws kms list-aliases \
        --query "Aliases[?contains(AliasName, 'jenkins')].AliasName" \
        --output text \
        --region $REGION)
    
    if [ -n "$KMS_ALIAS" ]; then
        test_pass "KMS key configured: $KMS_ALIAS"
    else
        test_warn "KMS key not found"
    fi
    
    # VPC Flow Logs
    FLOW_LOGS=$(aws ec2 describe-flow-logs \
        --filter "Name=tag:Environment,Values=$ENVIRONMENT" \
        --query 'FlowLogs[0].FlowLogStatus' \
        --output text \
        --region $REGION)
    
    if [ "$FLOW_LOGS" == "ACTIVE" ]; then
        test_pass "VPC Flow Logs enabled"
    else
        test_warn "VPC Flow Logs not active"
    fi
    
    # EBS encryption
    UNENCRYPTED=$(aws ec2 describe-volumes \
        --filters "Name=tag:Environment,Values=$ENVIRONMENT" "Name=encrypted,Values=false" \
        --query 'length(Volumes)' \
        --output text \
        --region $REGION)
    
    if [ "$UNENCRYPTED" == "0" ]; then
        test_pass "All EBS volumes encrypted"
    else
        test_fail "Found $UNENCRYPTED unencrypted volumes"
    fi
}

# Test Backup
test_backup() {
    print_header "Testing Backup & DR"
    
    # Backup plan
    BACKUP_PLAN=$(aws backup list-backup-plans \
        --query "BackupPlansList[?contains(BackupPlanName, 'jenkins')].BackupPlanName" \
        --output text \
        --region $REGION)
    
    if [ -n "$BACKUP_PLAN" ]; then
        test_pass "Backup plan configured: $BACKUP_PLAN"
    else
        test_warn "Backup plan not found"
    fi
    
    # S3 backup bucket
    BACKUP_BUCKET=$(aws s3 ls | grep jenkins-backup | awk '{print $3}')
    
    if [ -n "$BACKUP_BUCKET" ]; then
        test_pass "Backup S3 bucket exists: $BACKUP_BUCKET"
    else
        test_warn "Backup S3 bucket not found"
    fi
}

# Generate report
generate_report() {
    print_header "Test Summary"
    
    TOTAL=$((PASSED + FAILED + WARNINGS))
    
    echo -e "${GREEN}Passed:${NC}   $PASSED"
    echo -e "${RED}Failed:${NC}   $FAILED"
    echo -e "${YELLOW}Warnings:${NC} $WARNINGS"
    echo -e "Total:    $TOTAL"
    echo ""
    
    if [ $FAILED -eq 0 ]; then
        echo -e "${GREEN}✓ All critical tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}✗ Some tests failed. Please review.${NC}"
        exit 1
    fi
}

# Main execution
main() {
    echo -e "${YELLOW}"
    echo "╔════════════════════════════════════════════════╗"
    echo "║  Jenkins Enterprise Platform - Test Suite     ║"
    echo "║  Environment: $ENVIRONMENT                          ║"
    echo "║  Region: $REGION                         ║"
    echo "╚════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    case $COMPONENT in
        vpc)
            test_vpc
            ;;
        security)
            test_security_groups
            ;;
        efs)
            test_efs
            ;;
        alb)
            test_alb
            ;;
        asg|autoscaling)
            test_autoscaling
            ;;
        jenkins)
            test_jenkins
            ;;
        lambda|blue-green)
            test_lambda
            ;;
        cloudwatch|monitoring)
            test_cloudwatch
            ;;
        backup)
            test_backup
            ;;
        all)
            test_vpc
            test_security_groups
            test_efs
            test_alb
            test_autoscaling
            test_jenkins
            test_lambda
            test_cloudwatch
            test_security
            test_backup
            ;;
        *)
            echo "Unknown component: $COMPONENT"
            echo "Usage: $0 [vpc|security|efs|alb|asg|jenkins|lambda|cloudwatch|backup|all]"
            exit 1
            ;;
    esac
    
    generate_report
}

# Run tests
main
