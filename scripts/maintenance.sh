#!/bin/bash

# Jenkins Enterprise Platform - Maintenance Script
# Usage: ./maintenance.sh [command]

set -e

ENVIRONMENT="staging"
PROJECT_NAME="jenkins-enterprise-platform"
REGION="us-east-1"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
print_header() {
    echo -e "${BLUE}=== Jenkins Enterprise Platform Maintenance ===${NC}"
    echo -e "${BLUE}Environment: ${ENVIRONMENT}${NC}"
    echo -e "${BLUE}Region: ${REGION}${NC}"
    echo ""
}

show_status() {
    echo -e "${YELLOW}Checking infrastructure status...${NC}"
    
    # Get Terraform outputs
    echo -e "${GREEN}Terraform Outputs:${NC}"
    terraform output
    echo ""
    
    # Check Auto Scaling Group
    echo -e "${GREEN}Auto Scaling Group Status:${NC}"
    aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names "${ENVIRONMENT}-${PROJECT_NAME}-asg" \
        --region ${REGION} \
        --query 'AutoScalingGroups[0].{DesiredCapacity:DesiredCapacity,Instances:Instances[*].{InstanceId:InstanceId,HealthStatus:HealthStatus,LifecycleState:LifecycleState}}' \
        --output table
    echo ""
    
    # Check Target Group Health
    echo -e "${GREEN}Load Balancer Target Health:${NC}"
    TARGET_GROUP_ARN=$(terraform output -raw load_balancer_dns_name | xargs -I {} aws elbv2 describe-target-groups --names "${ENVIRONMENT}-jenkins-tg" --region ${REGION} --query 'TargetGroups[0].TargetGroupArn' --output text)
    aws elbv2 describe-target-health \
        --target-group-arn ${TARGET_GROUP_ARN} \
        --region ${REGION} \
        --query 'TargetHealthDescriptions[*].{InstanceId:Target.Id,Health:TargetHealth.State,Reason:TargetHealth.Reason}' \
        --output table
}

get_password() {
    echo -e "${YELLOW}Retrieving Jenkins admin password...${NC}"
    aws ssm get-parameter \
        --name "/jenkins/${ENVIRONMENT}/admin-password" \
        --with-decryption \
        --query 'Parameter.Value' \
        --output text \
        --region ${REGION} 2>/dev/null || echo -e "${RED}Password not yet available. Jenkins may still be initializing.${NC}"
}

show_logs() {
    echo -e "${YELLOW}Recent Jenkins initialization logs:${NC}"
    aws logs describe-log-streams \
        --log-group-name "/jenkins/${ENVIRONMENT}/user-data" \
        --region ${REGION} \
        --query 'logStreams[0].logStreamName' \
        --output text 2>/dev/null | xargs -I {} aws logs get-log-events \
        --log-group-name "/jenkins/${ENVIRONMENT}/user-data" \
        --log-stream-name {} \
        --region ${REGION} \
        --query 'events[-10:].message' \
        --output text 2>/dev/null || echo -e "${RED}No logs available yet.${NC}"
}

show_help() {
    echo -e "${GREEN}Available commands:${NC}"
    echo "  status    - Show infrastructure status"
    echo "  password  - Get Jenkins admin password"
    echo "  logs      - Show recent initialization logs"
    echo "  url       - Show Jenkins URL"
    echo "  help      - Show this help message"
    echo ""
    echo -e "${GREEN}Examples:${NC}"
    echo "  ./maintenance.sh status"
    echo "  ./maintenance.sh password"
    echo "  ./maintenance.sh logs"
}

show_url() {
    echo -e "${YELLOW}Jenkins URL:${NC}"
    terraform output -raw jenkins_url
    echo ""
}

# Main script
print_header

case "${1:-help}" in
    "status")
        show_status
        ;;
    "password")
        get_password
        ;;
    "logs")
        show_logs
        ;;
    "url")
        show_url
        ;;
    "help"|*)
        show_help
        ;;
esac
