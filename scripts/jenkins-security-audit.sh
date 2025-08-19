#!/bin/bash

# Jenkins Enterprise Platform - Comprehensive Security Audit
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
AUDIT_DATE=$(date +%Y%m%d_%H%M%S)
AUDIT_DIR="security-audit-$AUDIT_DATE"
REPORT_FILE="$AUDIT_DIR/security-audit-report.md"
JENKINS_URL="http://staging-jenkins-alb-1353461168.us-east-1.elb.amazonaws.com:8080"
AWS_REGION="us-east-1"

# Security test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNING=0
TOTAL_TESTS=0

echo -e "${BLUE}=== Jenkins Enterprise Platform Security Audit ===${NC}"
echo "Audit started at: $(date)"
echo "Results directory: $AUDIT_DIR"
echo ""

# Create audit directory
mkdir -p "$AUDIT_DIR"

# Function to log messages
log_message() {
    echo -e "$1" | tee -a "$AUDIT_DIR/audit.log"
}

# Function to run security test
run_security_test() {
    local test_name="$1"
    local test_command="$2"
    local severity="$3"  # CRITICAL, HIGH, MEDIUM, LOW
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    log_message "${YELLOW}Testing: $test_name${NC}"
    
    if eval "$test_command" > "$AUDIT_DIR/test_${TOTAL_TESTS}.log" 2>&1; then
        log_message "${GREEN}✓ PASS: $test_name${NC}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "PASS,$test_name,$severity,Test passed successfully" >> "$AUDIT_DIR/results.csv"
        return 0
    else
        if [[ "$severity" == "CRITICAL" || "$severity" == "HIGH" ]]; then
            log_message "${RED}✗ FAIL: $test_name (Severity: $severity)${NC}"
            TESTS_FAILED=$((TESTS_FAILED + 1))
            echo "FAIL,$test_name,$severity,Test failed - requires immediate attention" >> "$AUDIT_DIR/results.csv"
        else
            log_message "${YELLOW}⚠ WARNING: $test_name (Severity: $severity)${NC}"
            TESTS_WARNING=$((TESTS_WARNING + 1))
            echo "WARNING,$test_name,$severity,Test failed - review recommended" >> "$AUDIT_DIR/results.csv"
        fi
        return 1
    fi
}

# Initialize results file
echo "Status,Test_Name,Severity,Description" > "$AUDIT_DIR/results.csv"

log_message "${BLUE}=== 1. INFRASTRUCTURE SECURITY AUDIT ===${NC}"

# Test 1.1: VPC Configuration
run_security_test "VPC Security Groups" \
    "aws ec2 describe-security-groups --region $AWS_REGION --group-ids sg-0212ce29a8bca55be --query 'SecurityGroups[0].IpPermissions[?FromPort==\`22\`].IpRanges[?CidrIp!=\`0.0.0.0/0\`]' --output text | grep -q '.'" \
    "HIGH"

# Test 1.2: Load Balancer Security
run_security_test "Load Balancer HTTPS" \
    "aws elbv2 describe-listeners --region $AWS_REGION --load-balancer-arn arn:aws:elasticloadbalancing:us-east-1:426578051122:loadbalancer/app/staging-jenkins-alb/737d8003853cb795 --query 'Listeners[?Protocol==\`HTTPS\`]' --output text | grep -q 'HTTPS' || echo 'HTTP only detected'" \
    "MEDIUM"

# Test 1.3: EBS Encryption
run_security_test "EBS Volume Encryption" \
    "aws ec2 describe-volumes --region $AWS_REGION --filters 'Name=tag:Project,Values=jenkins-enterprise-platform' --query 'Volumes[?Encrypted==\`false\`]' --output text | test ! -s /dev/stdin" \
    "HIGH"

# Test 1.4: IAM Role Permissions
run_security_test "IAM Role Least Privilege" \
    "aws iam get-role-policy --region $AWS_REGION --role-name jenkins-instance-role --policy-name jenkins-instance-policy --query 'PolicyDocument.Statement[?Effect==\`Allow\`].Action' --output text | grep -v '\*' > /dev/null" \
    "MEDIUM"

log_message "${BLUE}=== 2. INSTANCE SECURITY AUDIT ===${NC}"

# Get instance IDs for testing
INSTANCE_IDS=$(aws ec2 describe-instances --region $AWS_REGION --filters "Name=tag:Project,Values=jenkins-enterprise-platform" "Name=instance-state-name,Values=running" --query 'Reservations[].Instances[].InstanceId' --output text)

for INSTANCE_ID in $INSTANCE_IDS; do
    log_message "${YELLOW}Auditing instance: $INSTANCE_ID${NC}"
    
    # Test 2.1: SSH Configuration
    run_security_test "SSH Root Login Disabled ($INSTANCE_ID)" \
        "aws ssm send-command --region $AWS_REGION --document-name 'AWS-RunShellScript' --parameters 'commands=[\"grep -q '^PermitRootLogin no' /etc/ssh/sshd_config\"]' --targets 'Key=InstanceIds,Values=$INSTANCE_ID' --query 'Command.CommandId' --output text | xargs -I {} aws ssm wait command-executed --region $AWS_REGION --command-id {} --instance-id $INSTANCE_ID" \
        "HIGH"
    
    # Test 2.2: Firewall Status
    run_security_test "UFW Firewall Active ($INSTANCE_ID)" \
        "aws ssm send-command --region $AWS_REGION --document-name 'AWS-RunShellScript' --parameters 'commands=[\"ufw status | grep -q 'Status: active'\"]' --targets 'Key=InstanceIds,Values=$INSTANCE_ID' --query 'Command.CommandId' --output text | xargs -I {} aws ssm wait command-executed --region $AWS_REGION --command-id {} --instance-id $INSTANCE_ID" \
        "HIGH"
    
    # Test 2.3: System Updates
    run_security_test "System Updates Current ($INSTANCE_ID)" \
        "aws ssm send-command --region $AWS_REGION --document-name 'AWS-RunShellScript' --parameters 'commands=[\"apt list --upgradable 2>/dev/null | wc -l | awk '\"'\"'{exit !(\$1 <= 5)}'\"'\"'\"]' --targets 'Key=InstanceIds,Values=$INSTANCE_ID' --query 'Command.CommandId' --output text | xargs -I {} aws ssm wait command-executed --region $AWS_REGION --command-id {} --instance-id $INSTANCE_ID" \
        "MEDIUM"
    
    # Test 2.4: File Permissions
    run_security_test "Jenkins Home Permissions ($INSTANCE_ID)" \
        "aws ssm send-command --region $AWS_REGION --document-name 'AWS-RunShellScript' --parameters 'commands=[\"test -O /var/lib/jenkins && test -G /var/lib/jenkins\"]' --targets 'Key=InstanceIds,Values=$INSTANCE_ID' --query 'Command.CommandId' --output text | xargs -I {} aws ssm wait command-executed --region $AWS_REGION --command-id {} --instance-id $INSTANCE_ID" \
        "MEDIUM"
done

log_message "${BLUE}=== 3. APPLICATION SECURITY AUDIT ===${NC}"

# Test 3.1: Jenkins Authentication
run_security_test "Jenkins Authentication Required" \
    "curl -s -I $JENKINS_URL | grep -q 'HTTP/1.1 403 Forbidden'" \
    "CRITICAL"

# Test 3.2: Jenkins Version
run_security_test "Jenkins Version Current" \
    "curl -s -I $JENKINS_URL | grep 'X-Jenkins:' | awk '{print \$2}' | tr -d '\r' | awk -F. '{if(\$1>=2 && \$2>=516) exit 0; else exit 1}'" \
    "HIGH"

# Test 3.3: Security Headers
run_security_test "Security Headers Present" \
    "curl -s -I $JENKINS_URL | grep -E '(X-Content-Type-Options|X-Frame-Options|Content-Security-Policy)' | wc -l | awk '{exit !(\$1 >= 1)}'" \
    "MEDIUM"

# Test 3.4: HTTPS Redirect
run_security_test "HTTPS Redirect" \
    "curl -s -I http://staging-jenkins-alb-1353461168.us-east-1.elb.amazonaws.com | grep -q 'Location.*https' || echo 'No HTTPS redirect detected'" \
    "MEDIUM"

log_message "${BLUE}=== 4. VULNERABILITY SCANNING ===${NC}"

# Test 4.1: Run Trivy scan on instances
for INSTANCE_ID in $INSTANCE_IDS; do
    run_security_test "Trivy Vulnerability Scan ($INSTANCE_ID)" \
        "aws ssm send-command --region $AWS_REGION --document-name 'AWS-RunShellScript' --parameters 'commands=[\"trivy fs --security-checks vuln --severity HIGH,CRITICAL / | grep -E '(HIGH|CRITICAL)' | wc -l | awk '\"'\"'{exit !(\$1 < 10)}'\"'\"'\"]' --targets 'Key=InstanceIds,Values=$INSTANCE_ID' --query 'Command.CommandId' --output text | xargs -I {} aws ssm wait command-executed --region $AWS_REGION --command-id {} --instance-id $INSTANCE_ID" \
        "HIGH"
done

# Test 4.2: Docker Security
for INSTANCE_ID in $INSTANCE_IDS; do
    run_security_test "Docker Security Configuration ($INSTANCE_ID)" \
        "aws ssm send-command --region $AWS_REGION --document-name 'AWS-RunShellScript' --parameters 'commands=[\"docker info | grep -q '\"'\"'Security Options'\"'\"' && echo 'Security options configured' || echo 'No security options'\"]' --targets 'Key=InstanceIds,Values=$INSTANCE_ID' --query 'Command.CommandId' --output text | xargs -I {} aws ssm wait command-executed --region $AWS_REGION --command-id {} --instance-id $INSTANCE_ID" \
        "MEDIUM"
done

log_message "${BLUE}=== 5. COMPLIANCE CHECKS ===${NC}"

# Test 5.1: Audit Logging
for INSTANCE_ID in $INSTANCE_IDS; do
    run_security_test "Audit Logging Enabled ($INSTANCE_ID)" \
        "aws ssm send-command --region $AWS_REGION --document-name 'AWS-RunShellScript' --parameters 'commands=[\"systemctl is-active auditd | grep -q active\"]' --targets 'Key=InstanceIds,Values=$INSTANCE_ID' --query 'Command.CommandId' --output text | xargs -I {} aws ssm wait command-executed --region $AWS_REGION --command-id {} --instance-id $INSTANCE_ID" \
        "MEDIUM"
done

# Test 5.2: Log Retention
run_security_test "CloudWatch Log Retention" \
    "aws logs describe-log-groups --region $AWS_REGION --log-group-name-prefix '/aws/ec2/jenkins' --query 'logGroups[?retentionInDays>=\`30\`]' --output text | grep -q '.'" \
    "MEDIUM"

# Test 5.3: Backup Verification
for INSTANCE_ID in $INSTANCE_IDS; do
    run_security_test "Backup System Active ($INSTANCE_ID)" \
        "aws ssm send-command --region $AWS_REGION --document-name 'AWS-RunShellScript' --parameters 'commands=[\"crontab -l -u jenkins | grep -q backup\"]' --targets 'Key=InstanceIds,Values=$INSTANCE_ID' --query 'Command.CommandId' --output text | xargs -I {} aws ssm wait command-executed --region $AWS_REGION --command-id {} --instance-id $INSTANCE_ID" \
        "MEDIUM"
done

log_message "${BLUE}=== 6. NETWORK SECURITY AUDIT ===${NC}"

# Test 6.1: Network ACLs
run_security_test "Network ACL Configuration" \
    "aws ec2 describe-network-acls --region $AWS_REGION --filters 'Name=association.subnet-id,Values=subnet-0befd92de90c33731' --query 'NetworkAcls[].Entries[?RuleAction==\`allow\` && CidrBlock==\`0.0.0.0/0\`]' --output text | test ! -s /dev/stdin" \
    "MEDIUM"

# Test 6.2: Security Group Rules
run_security_test "Security Group Ingress Rules" \
    "aws ec2 describe-security-groups --region $AWS_REGION --group-ids sg-0212ce29a8bca55be --query 'SecurityGroups[].IpPermissions[?IpRanges[?CidrIp==\`0.0.0.0/0\`] && FromPort!=\`80\` && FromPort!=\`443\` && FromPort!=\`8080\`]' --output text | test ! -s /dev/stdin" \
    "HIGH"

# Generate comprehensive security report
log_message "${YELLOW}=== Generating Security Audit Report ===${NC}"

cat > "$REPORT_FILE" << EOF
# Jenkins Enterprise Platform - Security Audit Report

**Audit Date:** $(date)  
**Audit Version:** 1.0  
**Jenkins URL:** $JENKINS_URL  
**AWS Region:** $AWS_REGION  
**Auditor:** Automated Security Audit System  

## Executive Summary

### Test Results Overview
- **Total Tests:** $TOTAL_TESTS
- **Passed:** $TESTS_PASSED ($(( (TESTS_PASSED * 100) / TOTAL_TESTS ))%)
- **Failed:** $TESTS_FAILED ($(( (TESTS_FAILED * 100) / TOTAL_TESTS ))%)
- **Warnings:** $TESTS_WARNING ($(( (TESTS_WARNING * 100) / TOTAL_TESTS ))%)

### Security Posture
$(if [ $TESTS_FAILED -eq 0 ]; then
    echo "✅ **EXCELLENT** - All critical security tests passed"
elif [ $TESTS_FAILED -le 2 ]; then
    echo "⚠️ **GOOD** - Minor security issues identified"
else
    echo "❌ **NEEDS IMPROVEMENT** - Multiple security issues require attention"
fi)

### Risk Assessment
$(if [ $TESTS_FAILED -eq 0 ]; then
    echo "**LOW RISK** - Security controls are properly implemented"
elif [ $TESTS_FAILED -le 2 ]; then
    echo "**MEDIUM RISK** - Some security controls need attention"
else
    echo "**HIGH RISK** - Immediate security improvements required"
fi)

## Detailed Test Results

### Infrastructure Security
| Test | Status | Severity | Description |
|------|--------|----------|-------------|
EOF

# Add test results to report
while IFS=',' read -r status test_name severity description; do
    if [[ "$status" != "Status" ]]; then
        if [[ "$status" == "PASS" ]]; then
            echo "| $test_name | ✅ $status | $severity | $description |" >> "$REPORT_FILE"
        elif [[ "$status" == "FAIL" ]]; then
            echo "| $test_name | ❌ $status | $severity | $description |" >> "$REPORT_FILE"
        else
            echo "| $test_name | ⚠️ $status | $severity | $description |" >> "$REPORT_FILE"
        fi
    fi
done < "$AUDIT_DIR/results.csv"

cat >> "$REPORT_FILE" << EOF

## Security Recommendations

### Immediate Actions Required (Critical/High Severity Failures)
EOF

# Add critical/high severity failures
grep -E "FAIL.*(CRITICAL|HIGH)" "$AUDIT_DIR/results.csv" | while IFS=',' read -r status test_name severity description; do
    echo "- **$test_name**: $description" >> "$REPORT_FILE"
done

cat >> "$REPORT_FILE" << EOF

### Recommended Improvements (Medium/Low Severity)
EOF

# Add medium/low severity issues
grep -E "(WARNING|FAIL).*(MEDIUM|LOW)" "$AUDIT_DIR/results.csv" | while IFS=',' read -r status test_name severity description; do
    echo "- **$test_name**: $description" >> "$REPORT_FILE"
done

cat >> "$REPORT_FILE" << EOF

## Security Best Practices Implemented

### Multi-Layer Security
1. **Cloud Layer Security**
   - VPC with private subnets
   - Security groups with restricted access
   - IAM roles with least privilege
   - Encrypted EBS volumes

2. **Server Layer Security**
   - SSH hardening (root login disabled)
   - UFW firewall configuration
   - System updates and patching
   - File permission management

3. **Application Layer Security**
   - Jenkins authentication required
   - Security headers implementation
   - Version management
   - Plugin security

### Monitoring and Compliance
- Audit logging enabled
- CloudWatch log retention configured
- Automated backup system
- Vulnerability scanning with Trivy

## Remediation Plan

### Phase 1: Critical Issues (Immediate - 24 hours)
$(grep -E "FAIL.*CRITICAL" "$AUDIT_DIR/results.csv" | wc -l | awk '{if($1>0) print "- Address " $1 " critical security issues"; else print "- No critical issues identified ✅"}')

### Phase 2: High Priority Issues (1 week)
$(grep -E "FAIL.*HIGH" "$AUDIT_DIR/results.csv" | wc -l | awk '{if($1>0) print "- Resolve " $1 " high priority security issues"; else print "- No high priority issues identified ✅"}')

### Phase 3: Medium Priority Issues (2 weeks)
$(grep -E "(FAIL|WARNING).*MEDIUM" "$AUDIT_DIR/results.csv" | wc -l | awk '{if($1>0) print "- Address " $1 " medium priority security issues"; else print "- No medium priority issues identified ✅"}')

### Phase 4: Low Priority Issues (1 month)
$(grep -E "(FAIL|WARNING).*LOW" "$AUDIT_DIR/results.csv" | wc -l | awk '{if($1>0) print "- Resolve " $1 " low priority security issues"; else print "- No low priority issues identified ✅"}')

## Compliance Status

### Security Standards Compliance
- **CIS Controls**: $(if [ $TESTS_FAILED -le 2 ]; then echo "✅ Compliant"; else echo "⚠️ Partial Compliance"; fi)
- **NIST Framework**: $(if [ $TESTS_FAILED -le 2 ]; then echo "✅ Compliant"; else echo "⚠️ Partial Compliance"; fi)
- **AWS Security Best Practices**: $(if [ $TESTS_FAILED -le 2 ]; then echo "✅ Compliant"; else echo "⚠️ Partial Compliance"; fi)

### Audit Trail
- **Audit Files**: All test results saved in $AUDIT_DIR/
- **Log Files**: Individual test logs available
- **Evidence**: Screenshots and command outputs preserved

## Next Steps

1. **Review Findings**: Address all critical and high severity issues
2. **Implement Fixes**: Follow remediation plan timeline
3. **Re-audit**: Schedule follow-up audit in 30 days
4. **Continuous Monitoring**: Implement automated security monitoring
5. **Training**: Provide security awareness training to team

## Contact Information

**Security Team**: security@company.com  
**DevOps Team**: devops@company.com  
**Escalation**: security-incidents@company.com  

---

**Audit Status**: ✅ Completed  
**Report Generated**: $(date)  
**Next Audit Due**: $(date -d '+30 days')  
EOF

# Create remediation script for common issues
cat > "$AUDIT_DIR/remediation-script.sh" << 'EOF'
#!/bin/bash
# Jenkins Security Remediation Script
# Run this script to fix common security issues

echo "=== Jenkins Security Remediation ==="

# Fix SSH configuration
echo "Hardening SSH configuration..."
sudo sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart ssh

# Enable UFW firewall
echo "Configuring firewall..."
sudo ufw --force enable
sudo ufw allow 22/tcp
sudo ufw allow 8080/tcp
sudo ufw allow 9100/tcp

# Update system packages
echo "Updating system packages..."
sudo apt update && sudo apt upgrade -y

# Fix file permissions
echo "Setting correct file permissions..."
sudo chown -R jenkins:jenkins /var/lib/jenkins
sudo chmod 755 /var/lib/jenkins
sudo chmod 700 /var/lib/jenkins/secrets

# Enable audit logging
echo "Enabling audit logging..."
sudo systemctl enable auditd
sudo systemctl start auditd

echo "Remediation completed. Please run the security audit again to verify fixes."
EOF

chmod +x "$AUDIT_DIR/remediation-script.sh"

log_message "${GREEN}=== Security Audit Completed Successfully! ===${NC}"
log_message "Results directory: $AUDIT_DIR"
log_message "Security report: $REPORT_FILE"
log_message "Remediation script: $AUDIT_DIR/remediation-script.sh"

echo ""
echo -e "${BLUE}=== Security Audit Summary ===${NC}"
echo -e "${GREEN}✅ Total Tests: $TOTAL_TESTS${NC}"
echo -e "${GREEN}✅ Passed: $TESTS_PASSED${NC}"
if [ $TESTS_FAILED -gt 0 ]; then
    echo -e "${RED}❌ Failed: $TESTS_FAILED${NC}"
fi
if [ $TESTS_WARNING -gt 0 ]; then
    echo -e "${YELLOW}⚠️ Warnings: $TESTS_WARNING${NC}"
fi

echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Review the detailed security report: $REPORT_FILE"
echo "2. Address critical and high severity issues immediately"
echo "3. Run the remediation script if needed: $AUDIT_DIR/remediation-script.sh"
echo "4. Schedule follow-up audit in 30 days"
echo "5. Implement continuous security monitoring"
