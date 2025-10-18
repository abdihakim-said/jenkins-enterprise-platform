#!/bin/bash

# Jenkins Initialization Monitor
# Tracks the progress of Jenkins startup

set -e

ENVIRONMENT="staging"
PROJECT_NAME="jenkins-enterprise-platform"
REGION="us-east-1"
JENKINS_URL="http://staging-jenkins-alb-1547278824.us-east-1.elb.amazonaws.com:8080"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    clear
    echo -e "${BLUE}🔍 Jenkins Initialization Monitor${NC}"
    echo -e "${BLUE}Environment: ${ENVIRONMENT}${NC}"
    echo -e "${BLUE}URL: ${JENKINS_URL}${NC}"
    echo -e "${BLUE}Time: $(date -u '+%Y-%m-%d %H:%M:%S UTC')${NC}"
    echo ""
}

check_target_health() {
    echo -e "${YELLOW}🎯 Load Balancer Target Health:${NC}"
    TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups --names "${ENVIRONMENT}-jenkins-tg" --region ${REGION} --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null)
    
    if [ "$TARGET_GROUP_ARN" != "None" ]; then
        aws elbv2 describe-target-health \
            --target-group-arn ${TARGET_GROUP_ARN} \
            --region ${REGION} \
            --query 'TargetHealthDescriptions[*].{Instance:Target.Id,Health:TargetHealth.State,Reason:TargetHealth.Reason}' \
            --output table 2>/dev/null || echo -e "${RED}Unable to check target health${NC}"
    else
        echo -e "${RED}Target group not found${NC}"
    fi
    echo ""
}

check_jenkins_response() {
    echo -e "${YELLOW}🌐 Jenkins HTTP Response:${NC}"
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 ${JENKINS_URL} 2>/dev/null || echo "000")
    
    case $HTTP_STATUS in
        "200")
            echo -e "${GREEN}✅ Jenkins is responding (HTTP 200)${NC}"
            return 0
            ;;
        "403")
            echo -e "${GREEN}✅ Jenkins is up but initializing (HTTP 403)${NC}"
            return 0
            ;;
        "503")
            echo -e "${YELLOW}⏳ Jenkins is starting up (HTTP 503)${NC}"
            ;;
        "000")
            echo -e "${RED}❌ No response (Connection timeout/refused)${NC}"
            ;;
        *)
            echo -e "${YELLOW}⚠️  Unexpected response (HTTP ${HTTP_STATUS})${NC}"
            ;;
    esac
    return 1
}

check_logs() {
    echo -e "${YELLOW}📋 Recent Initialization Logs:${NC}"
    LOG_STREAM=$(aws logs describe-log-streams \
        --log-group-name "/jenkins/${ENVIRONMENT}/user-data" \
        --region ${REGION} \
        --query 'logStreams[0].logStreamName' \
        --output text 2>/dev/null)
    
    if [ "$LOG_STREAM" != "None" ] && [ "$LOG_STREAM" != "" ]; then
        echo -e "${GREEN}📝 Log stream found: ${LOG_STREAM}${NC}"
        aws logs get-log-events \
            --log-group-name "/jenkins/${ENVIRONMENT}/user-data" \
            --log-stream-name "$LOG_STREAM" \
            --region ${REGION} \
            --query 'events[-5:].message' \
            --output text 2>/dev/null | tail -5 || echo -e "${YELLOW}No recent log entries${NC}"
    else
        echo -e "${YELLOW}📝 No log streams available yet${NC}"
    fi
    echo ""
}

check_instance_status() {
    echo -e "${YELLOW}🖥️  Instance Status:${NC}"
    INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names "${ENVIRONMENT}-${PROJECT_NAME}-asg" \
        --region ${REGION} \
        --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService`].InstanceId' \
        --output text 2>/dev/null)
    
    if [ "$INSTANCE_ID" != "" ] && [ "$INSTANCE_ID" != "None" ]; then
        echo -e "${GREEN}Instance ID: ${INSTANCE_ID}${NC}"
        
        # Get instance launch time
        LAUNCH_TIME=$(aws ec2 describe-instances \
            --instance-ids ${INSTANCE_ID} \
            --region ${REGION} \
            --query 'Reservations[0].Instances[0].LaunchTime' \
            --output text 2>/dev/null)
        
        if [ "$LAUNCH_TIME" != "" ]; then
            echo -e "${BLUE}Launch Time: ${LAUNCH_TIME}${NC}"
            
            # Calculate uptime
            LAUNCH_EPOCH=$(date -d "$LAUNCH_TIME" +%s 2>/dev/null || echo "0")
            CURRENT_EPOCH=$(date +%s)
            UPTIME_SECONDS=$((CURRENT_EPOCH - LAUNCH_EPOCH))
            UPTIME_MINUTES=$((UPTIME_SECONDS / 60))
            
            echo -e "${BLUE}Uptime: ${UPTIME_MINUTES} minutes${NC}"
        fi
    else
        echo -e "${RED}No healthy instances found${NC}"
    fi
    echo ""
}

main_loop() {
    local max_attempts=60  # 30 minutes (30 seconds * 60)
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        print_header
        
        echo -e "${BLUE}📊 Attempt ${attempt}/${max_attempts}${NC}"
        echo ""
        
        check_instance_status
        check_target_health
        
        if check_jenkins_response; then
            echo ""
            echo -e "${GREEN}🎉 Jenkins is ready!${NC}"
            echo -e "${GREEN}🌐 Access Jenkins at: ${JENKINS_URL}${NC}"
            echo ""
            echo -e "${YELLOW}📋 To get admin password:${NC}"
            echo -e "${BLUE}aws ssm get-parameter --name '/jenkins/${ENVIRONMENT}/admin-password' --with-decryption --query 'Parameter.Value' --output text --region ${REGION}${NC}"
            exit 0
        fi
        
        check_logs
        
        echo -e "${YELLOW}⏳ Waiting 30 seconds before next check...${NC}"
        sleep 30
        attempt=$((attempt + 1))
    done
    
    echo -e "${RED}❌ Jenkins did not become ready within 30 minutes${NC}"
    echo -e "${YELLOW}💡 Check CloudWatch logs for more details${NC}"
    exit 1
}

# Handle Ctrl+C gracefully
trap 'echo -e "\n${YELLOW}Monitoring stopped by user${NC}"; exit 0' INT

# Start monitoring
main_loop
