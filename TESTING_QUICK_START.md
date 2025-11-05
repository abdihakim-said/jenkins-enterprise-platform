# Testing Quick Start

## 🚀 Run All Tests (5 minutes)

```bash
# Automated test suite
./scripts/test-platform.sh

# Test specific component
./scripts/test-platform.sh jenkins
./scripts/test-platform.sh blue-green
```

---

## ✅ Essential Health Checks (30 seconds)

```bash
# 1. Jenkins accessible
curl -I http://dev-jenkins-alb-121130223.us-east-1.elb.amazonaws.com:8080

# 2. Target health
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw target_group_arn) \
  --region us-east-1

# 3. ASG status
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names dev-jenkins-enterprise-platform-asg \
  --query 'AutoScalingGroups[0].[DesiredCapacity,Instances[*].HealthStatus]' \
  --region us-east-1

# 4. Get admin password
aws ssm get-parameter \
  --name '/jenkins/dev/admin-password' \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text \
  --region us-east-1
```

---

## 🔵🟢 Blue-Green Deployment Test (8 minutes)

```bash
# 1. Check current state
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names \
    jenkins-enterprise-platform-dev-blue-asg \
    jenkins-enterprise-platform-dev-green-asg \
  --query 'AutoScalingGroups[*].[AutoScalingGroupName,DesiredCapacity]' \
  --output table \
  --region us-east-1

# 2. Trigger deployment
aws lambda invoke \
  --function-name jenkins-enterprise-platform-dev-deployment-orchestrator \
  --region us-east-1 \
  response.json && cat response.json

# 3. Monitor (watch for 5-8 minutes)
watch -n 10 'aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names \
    jenkins-enterprise-platform-dev-blue-asg \
    jenkins-enterprise-platform-dev-green-asg \
  --query "AutoScalingGroups[*].[AutoScalingGroupName,DesiredCapacity]" \
  --output table \
  --region us-east-1'

# 4. Verify zero downtime
while true; do
  curl -s -o /dev/null -w "%{http_code}\n" \
    http://dev-jenkins-alb-121130223.us-east-1.elb.amazonaws.com:8080
  sleep 2
done
```

**Expected**: Blue→Green or Green→Blue switch with 100% HTTP 200/403 responses

---

## 🔒 Security Validation (2 minutes)

```bash
# 1. All volumes encrypted
aws ec2 describe-volumes \
  --filters "Name=tag:Environment,Values=dev" \
  --query 'Volumes[*].[VolumeId,Encrypted]' \
  --region us-east-1

# 2. EFS encrypted
aws efs describe-file-systems \
  --query 'FileSystems[?Tags[?Key==`Environment` && Value==`dev`]].[FileSystemId,Encrypted]' \
  --region us-east-1

# 3. VPC Flow Logs active
aws ec2 describe-flow-logs \
  --filter "Name=tag:Environment,Values=dev" \
  --query 'FlowLogs[*].[FlowLogId,FlowLogStatus]' \
  --region us-east-1

# 4. No open security groups
aws ec2 describe-security-groups \
  --filters "Name=tag:Environment,Values=dev" \
  --query 'SecurityGroups[*].IpPermissions[?contains(IpRanges[].CidrIp, `0.0.0.0/0`)]' \
  --region us-east-1
```

**Expected**: All encrypted, Flow Logs active, no 0.0.0.0/0 on port 22

---

## 📊 Monitoring Check (1 minute)

```bash
# 1. Dashboard exists
aws cloudwatch list-dashboards \
  --query 'DashboardEntries[?contains(DashboardName, `dev-jenkins`)]' \
  --region us-east-1

# 2. Alarms configured
aws cloudwatch describe-alarms \
  --alarm-name-prefix dev-jenkins \
  --query 'MetricAlarms[*].[AlarmName,StateValue]' \
  --output table \
  --region us-east-1

# 3. Recent logs
aws logs tail /jenkins/dev/application --since 10m --region us-east-1
```

**Expected**: Dashboard, 3+ alarms, recent log entries

---

## 💾 Backup Verification (1 minute)

```bash
# 1. Backup plan exists
aws backup list-backup-plans \
  --query 'BackupPlansList[?contains(BackupPlanName, `jenkins`)]' \
  --region us-east-1

# 2. Recent backups
aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name Default \
  --query 'RecoveryPoints[?contains(ResourceArn, `jenkins`)].[CreationDate,Status]' \
  --region us-east-1

# 3. S3 backup bucket
aws s3 ls | grep jenkins-backup
```

**Expected**: Backup plan, recent recovery points, S3 bucket

---

## 🎯 End-to-End Test (10 minutes)

```bash
# 1. Deploy infrastructure
cd environments/dev
terraform apply -auto-approve

# 2. Wait for healthy targets (5-10 min)
watch -n 10 'aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw target_group_arn) \
  --region us-east-1'

# 3. Access Jenkins
JENKINS_URL=$(terraform output -raw jenkins_url)
ADMIN_PASS=$(aws ssm get-parameter \
  --name '/jenkins/dev/admin-password' \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text \
  --region us-east-1)

echo "URL: $JENKINS_URL"
echo "Password: $ADMIN_PASS"

# 4. Login and create test job
open $JENKINS_URL
```

---

## 🔥 Load Testing (5 minutes)

```bash
# Install Apache Bench
brew install apache-bench  # macOS
# sudo apt-get install apache2-utils  # Linux

# Run load test
ab -n 1000 -c 50 \
  http://dev-jenkins-alb-121130223.us-east-1.elb.amazonaws.com:8080/

# Monitor during load
watch -n 5 'aws cloudwatch get-metric-statistics \
  --namespace AWS/ApplicationELB \
  --metric-name TargetResponseTime \
  --dimensions Name=LoadBalancer,Value=app/dev-jenkins-alb/... \
  --start-time $(date -u -d "5 minutes ago" +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Average \
  --region us-east-1'
```

**Expected**: <2 second response time, no errors

---

## 🚨 Troubleshooting Commands

```bash
# Jenkins not accessible
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw target_group_arn) \
  --region us-east-1

# Check instance logs
INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names dev-jenkins-enterprise-platform-asg \
  --query 'AutoScalingGroups[0].Instances[0].InstanceId' \
  --output text \
  --region us-east-1)

aws ssm send-command \
  --instance-ids $INSTANCE_ID \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["tail -100 /var/log/cloud-init-output.log"]' \
  --region us-east-1

# Check EFS mount
aws ssm send-command \
  --instance-ids $INSTANCE_ID \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["df -h | grep efs","systemctl status jenkins"]' \
  --region us-east-1

# Lambda logs
aws logs tail /aws/lambda/jenkins-enterprise-platform-dev-deployment-orchestrator \
  --since 1h \
  --region us-east-1
```

---

## ✅ Success Criteria Checklist

- [ ] Jenkins accessible via ALB (HTTP 200/403)
- [ ] Admin password retrievable from SSM
- [ ] Target group shows healthy targets
- [ ] EFS mounted on instances
- [ ] Blue-green deployment completes in 5-8 minutes
- [ ] Zero downtime during deployment (100% uptime)
- [ ] All volumes encrypted
- [ ] CloudWatch dashboard and alarms configured
- [ ] Backup plan with recent recovery points
- [ ] Lambda orchestrator functional
- [ ] Response time <2 seconds under load
- [ ] Auto Scaling responds to load

---

## 📋 Test Results Template

```
Date: _______________
Tester: _______________
Environment: dev

Component Tests:
[ ] VPC & Network
[ ] Security Groups
[ ] EFS Storage
[ ] Load Balancer
[ ] Auto Scaling
[ ] Jenkins Application
[ ] Lambda Orchestrator
[ ] CloudWatch Monitoring
[ ] Security & Compliance
[ ] Backup & DR

Blue-Green Deployment:
[ ] Deployment triggered successfully
[ ] Zero downtime achieved
[ ] Health checks passed
[ ] Traffic switched correctly
[ ] Old environment scaled down

Performance:
[ ] Response time <2s
[ ] Load test passed (1000 requests)
[ ] Auto Scaling triggered correctly

Security:
[ ] All volumes encrypted
[ ] VPC Flow Logs active
[ ] No open security groups
[ ] IAM least privilege

Notes:
_________________________________
_________________________________
_________________________________

Overall Status: [ ] PASS  [ ] FAIL
```

---

**Full Documentation**: See `docs/TESTING_GUIDE.md`  
**Automated Tests**: Run `./scripts/test-platform.sh`
