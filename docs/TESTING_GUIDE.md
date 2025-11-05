# Jenkins Enterprise Platform - Testing Guide

## Quick Test Commands

### 1. Infrastructure Health Check
```bash
# Test all components
./scripts/test-platform.sh

# Test specific component
./scripts/test-platform.sh --component jenkins
```

---

## Component Testing Checklist

### ✅ VPC & Network (5 tests)

```bash
# 1. VPC exists
aws ec2 describe-vpcs \
  --filters "Name=tag:Environment,Values=dev" \
  --query 'Vpcs[0].VpcId' \
  --region us-east-1

# 2. Subnets in 3 AZs
aws ec2 describe-subnets \
  --filters "Name=tag:Environment,Values=dev" \
  --query 'Subnets[*].[SubnetId,AvailabilityZone,CidrBlock]' \
  --output table \
  --region us-east-1

# 3. NAT Gateway operational
aws ec2 describe-nat-gateways \
  --filter "Name=tag:Environment,Values=dev" \
  --query 'NatGateways[*].[NatGatewayId,State]' \
  --region us-east-1

# 4. Internet Gateway attached
aws ec2 describe-internet-gateways \
  --filters "Name=tag:Environment,Values=dev" \
  --query 'InternetGateways[*].[InternetGatewayId,Attachments[0].State]' \
  --region us-east-1

# 5. Route tables configured
aws ec2 describe-route-tables \
  --filters "Name=tag:Environment,Values=dev" \
  --query 'RouteTables[*].Routes[*].[DestinationCidrBlock,GatewayId]' \
  --region us-east-1
```

**Expected**: VPC with 6 subnets (3 public, 3 private), 1 NAT Gateway, 1 IGW

---

### ✅ Security Groups (3 tests)

```bash
# 1. ALB security group
aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=*alb*" "Name=tag:Environment,Values=dev" \
  --query 'SecurityGroups[*].[GroupId,GroupName,IpPermissions[*].[FromPort,ToPort]]' \
  --region us-east-1

# 2. Jenkins security group
aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=*jenkins*" "Name=tag:Environment,Values=dev" \
  --query 'SecurityGroups[*].[GroupId,GroupName,IpPermissions[*].[FromPort,ToPort]]' \
  --region us-east-1

# 3. EFS security group
aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=*efs*" "Name=tag:Environment,Values=dev" \
  --query 'SecurityGroups[*].[GroupId,GroupName,IpPermissions[*].[FromPort,ToPort]]' \
  --region us-east-1
```

**Expected**: ALB (port 8080), Jenkins (8080 from ALB), EFS (2049 from Jenkins)

---

### ✅ EFS Storage (4 tests)

```bash
# 1. EFS filesystem exists
aws efs describe-file-systems \
  --query 'FileSystems[?Tags[?Key==`Environment` && Value==`dev`]].[FileSystemId,LifeCycleState,SizeInBytes.Value]' \
  --region us-east-1

# 2. Mount targets in all AZs
aws efs describe-mount-targets \
  --file-system-id $(terraform output -raw efs_id) \
  --query 'MountTargets[*].[MountTargetId,AvailabilityZoneName,LifeCycleState]' \
  --region us-east-1

# 3. Access point configured
aws efs describe-access-points \
  --file-system-id $(terraform output -raw efs_id) \
  --query 'AccessPoints[*].[AccessPointId,LifeCycleState]' \
  --region us-east-1

# 4. EFS mounted on instance
INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names dev-jenkins-enterprise-platform-asg \
  --query 'AutoScalingGroups[0].Instances[0].InstanceId' \
  --output text \
  --region us-east-1)

aws ssm send-command \
  --instance-ids $INSTANCE_ID \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["df -h | grep efs","ls -la /var/lib/jenkins"]' \
  --region us-east-1
```

**Expected**: EFS available, 3 mount targets, mounted at /var/lib/jenkins

---

### ✅ Application Load Balancer (5 tests)

```bash
# 1. ALB exists and active
aws elbv2 describe-load-balancers \
  --names dev-jenkins-alb \
  --query 'LoadBalancers[*].[LoadBalancerName,State.Code,DNSName]' \
  --region us-east-1

# 2. Target group healthy
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw target_group_arn) \
  --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State,TargetHealth.Reason]' \
  --region us-east-1

# 3. Listener configured
aws elbv2 describe-listeners \
  --load-balancer-arn $(terraform output -raw alb_arn) \
  --query 'Listeners[*].[ListenerArn,Port,Protocol]' \
  --region us-east-1

# 4. ALB responds
ALB_DNS=$(terraform output -raw jenkins_url)
curl -I $ALB_DNS

# 5. Health check endpoint
curl -s $ALB_DNS/login | grep "Jenkins"
```

**Expected**: ALB active, targets healthy, port 8080 listener, HTTP 200 response

---

### ✅ Auto Scaling Groups (6 tests)

```bash
# 1. Main ASG configured
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names dev-jenkins-enterprise-platform-asg \
  --query 'AutoScalingGroups[*].[AutoScalingGroupName,DesiredCapacity,MinSize,MaxSize]' \
  --region us-east-1

# 2. Blue ASG configured
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names jenkins-enterprise-platform-dev-blue-asg \
  --query 'AutoScalingGroups[*].[AutoScalingGroupName,DesiredCapacity,Instances[*].HealthStatus]' \
  --region us-east-1

# 3. Green ASG configured
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names jenkins-enterprise-platform-dev-green-asg \
  --query 'AutoScalingGroups[*].[AutoScalingGroupName,DesiredCapacity,Instances[*].HealthStatus]' \
  --region us-east-1

# 4. Launch template uses latest AMI
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names dev-jenkins-enterprise-platform-asg \
  --query 'AutoScalingGroups[0].LaunchTemplate.[LaunchTemplateId,Version]' \
  --region us-east-1

# 5. Instances running
aws ec2 describe-instances \
  --filters "Name=tag:Environment,Values=dev" "Name=instance-state-name,Values=running" \
  --query 'Reservations[*].Instances[*].[InstanceId,ImageId,State.Name,LaunchTime]' \
  --output table \
  --region us-east-1

# 6. Scaling policies exist
aws autoscaling describe-policies \
  --auto-scaling-group-name dev-jenkins-enterprise-platform-asg \
  --query 'ScalingPolicies[*].[PolicyName,PolicyType,TargetTrackingConfiguration.TargetValue]' \
  --region us-east-1
```

**Expected**: Main ASG (1 instance), Blue ASG (1 instance), Green ASG (0 instances)

---

### ✅ Jenkins Application (8 tests)

```bash
# 1. Jenkins accessible
curl -I http://dev-jenkins-alb-121130223.us-east-1.elb.amazonaws.com:8080

# 2. Jenkins version
curl -s http://dev-jenkins-alb-121130223.us-east-1.elb.amazonaws.com:8080 | grep -o "Jenkins ver. [0-9.]*"

# 3. Get admin password
aws ssm get-parameter \
  --name '/jenkins/dev/admin-password' \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text \
  --region us-east-1

# 4. Jenkins service running
INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names dev-jenkins-enterprise-platform-asg \
  --query 'AutoScalingGroups[0].Instances[0].InstanceId' \
  --output text \
  --region us-east-1)

aws ssm send-command \
  --instance-ids $INSTANCE_ID \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["systemctl status jenkins"]' \
  --region us-east-1

# 5. Jenkins plugins installed
aws ssm send-command \
  --instance-ids $INSTANCE_ID \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["ls -1 /var/lib/jenkins/plugins/*.jpi | wc -l"]' \
  --region us-east-1

# 6. Jenkins logs
aws ssm send-command \
  --instance-ids $INSTANCE_ID \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["tail -20 /var/log/jenkins/jenkins.log"]' \
  --region us-east-1

# 7. Jenkins API test
JENKINS_URL="http://dev-jenkins-alb-121130223.us-east-1.elb.amazonaws.com:8080"
curl -s "$JENKINS_URL/api/json?pretty=true" | jq '.mode'

# 8. Test job creation (requires auth)
# Manual test: Login and create a test pipeline job
```

**Expected**: Jenkins running, accessible, plugins installed, API responding

---

### ✅ Lambda Blue-Green Orchestrator (5 tests)

```bash
# 1. Lambda function exists
aws lambda get-function \
  --function-name jenkins-enterprise-platform-dev-deployment-orchestrator \
  --query '[FunctionName,Runtime,State,LastUpdateStatus]' \
  --region us-east-1

# 2. Lambda has correct permissions
aws lambda get-policy \
  --function-name jenkins-enterprise-platform-dev-deployment-orchestrator \
  --region us-east-1

# 3. EventBridge rule configured
aws events list-rules \
  --name-prefix jenkins-enterprise-platform-dev \
  --query 'Rules[*].[Name,State,ScheduleExpression]' \
  --region us-east-1

# 4. Test Lambda invocation
aws lambda invoke \
  --function-name jenkins-enterprise-platform-dev-deployment-orchestrator \
  --payload '{"test": true}' \
  --region us-east-1 \
  response.json && cat response.json

# 5. Check Lambda logs
aws logs tail /aws/lambda/jenkins-enterprise-platform-dev-deployment-orchestrator \
  --since 1h \
  --region us-east-1
```

**Expected**: Lambda active, EventBridge rule enabled, successful test invocation

---

### ✅ CloudWatch Monitoring (6 tests)

```bash
# 1. Dashboard exists
aws cloudwatch list-dashboards \
  --query 'DashboardEntries[?contains(DashboardName, `dev-jenkins`)]' \
  --region us-east-1

# 2. Alarms configured
aws cloudwatch describe-alarms \
  --alarm-name-prefix dev-jenkins \
  --query 'MetricAlarms[*].[AlarmName,StateValue,MetricName]' \
  --output table \
  --region us-east-1

# 3. Log groups exist
aws logs describe-log-groups \
  --log-group-name-prefix /jenkins/dev \
  --query 'logGroups[*].[logGroupName,retentionInDays]' \
  --region us-east-1

# 4. Recent logs
aws logs tail /jenkins/dev/application --since 1h --region us-east-1

# 5. Metrics available
aws cloudwatch list-metrics \
  --namespace AWS/EC2 \
  --dimensions Name=AutoScalingGroupName,Value=dev-jenkins-enterprise-platform-asg \
  --region us-east-1

# 6. SNS topic for alerts
aws sns list-topics \
  --query 'Topics[?contains(TopicArn, `jenkins`)]' \
  --region us-east-1
```

**Expected**: Dashboard, alarms, log groups, metrics, SNS topic configured

---

### ✅ Backup & DR (4 tests)

```bash
# 1. AWS Backup plan exists
aws backup list-backup-plans \
  --query 'BackupPlansList[?contains(BackupPlanName, `jenkins`)]' \
  --region us-east-1

# 2. Recent backups
aws backup list-recovery-points-by-backup-vault \
  --backup-vault-name Default \
  --query 'RecoveryPoints[?contains(ResourceArn, `jenkins`)].[RecoveryPointArn,CreationDate,Status]' \
  --region us-east-1

# 3. S3 backup bucket
aws s3 ls | grep jenkins-backup

# 4. DR region AMI replication
aws ec2 describe-images \
  --owners self \
  --filters "Name=tag:Environment,Values=dev" \
  --query 'Images[*].[ImageId,Name,CreationDate]' \
  --region us-west-2
```

**Expected**: Backup plan, recent recovery points, S3 bucket, DR AMIs

---

### ✅ Security & Compliance (7 tests)

```bash
# 1. KMS key for encryption
aws kms list-aliases \
  --query 'Aliases[?contains(AliasName, `jenkins`)]' \
  --region us-east-1

# 2. EBS volumes encrypted
aws ec2 describe-volumes \
  --filters "Name=tag:Environment,Values=dev" \
  --query 'Volumes[*].[VolumeId,Encrypted,KmsKeyId]' \
  --region us-east-1

# 3. EFS encrypted
aws efs describe-file-systems \
  --query 'FileSystems[?Tags[?Key==`Environment` && Value==`dev`]].[FileSystemId,Encrypted,KmsKeyId]' \
  --region us-east-1

# 4. VPC Flow Logs enabled
aws ec2 describe-flow-logs \
  --filter "Name=tag:Environment,Values=dev" \
  --query 'FlowLogs[*].[FlowLogId,FlowLogStatus,ResourceId]' \
  --region us-east-1

# 5. IAM roles least privilege
aws iam get-role \
  --role-name dev-jenkins-enterprise-platform-role \
  --query 'Role.[RoleName,AssumeRolePolicyDocument]' \
  --region us-east-1

# 6. Security groups no 0.0.0.0/0 on sensitive ports
aws ec2 describe-security-groups \
  --filters "Name=tag:Environment,Values=dev" \
  --query 'SecurityGroups[*].IpPermissions[?contains(IpRanges[].CidrIp, `0.0.0.0/0`)]' \
  --region us-east-1

# 7. AWS Inspector findings
aws inspector2 list-findings \
  --filter-criteria '{"resourceTags":[{"key":"Environment","value":"dev"}]}' \
  --region us-east-1
```

**Expected**: KMS encryption, encrypted volumes, VPC Flow Logs, least privilege IAM

---

### ✅ Cost Optimization (4 tests)

```bash
# 1. Resource tagging
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Environment,Values=dev \
  --query 'ResourceTagMappingList[*].[ResourceARN,Tags]' \
  --region us-east-1 | grep jenkins

# 2. EFS lifecycle policy
aws efs describe-lifecycle-configuration \
  --file-system-id $(terraform output -raw efs_id) \
  --region us-east-1

# 3. S3 lifecycle policies
aws s3api get-bucket-lifecycle-configuration \
  --bucket $(terraform output -raw backup_bucket_name) \
  --region us-east-1

# 4. Single NAT Gateway (cost optimization)
aws ec2 describe-nat-gateways \
  --filter "Name=tag:Environment,Values=dev" \
  --query 'NatGateways[*].[NatGatewayId,State]' \
  --region us-east-1 | wc -l
```

**Expected**: All resources tagged, lifecycle policies, single NAT Gateway

---

## End-to-End Testing

### Test 1: Complete Deployment Flow
```bash
# 1. Deploy infrastructure
cd environments/dev
terraform plan
terraform apply -auto-approve

# 2. Wait for instances to be healthy (5-10 minutes)
watch -n 10 'aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw target_group_arn) \
  --region us-east-1'

# 3. Access Jenkins
JENKINS_URL=$(terraform output -raw jenkins_url)
echo "Jenkins URL: $JENKINS_URL"

# 4. Get admin password
aws ssm get-parameter \
  --name '/jenkins/dev/admin-password' \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text \
  --region us-east-1

# 5. Login and verify
open $JENKINS_URL
```

### Test 2: Blue-Green Deployment
```bash
# 1. Trigger deployment
aws lambda invoke \
  --function-name jenkins-enterprise-platform-dev-deployment-orchestrator \
  --region us-east-1 \
  response.json

# 2. Monitor deployment
watch -n 5 'aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names \
    jenkins-enterprise-platform-dev-blue-asg \
    jenkins-enterprise-platform-dev-green-asg \
  --query "AutoScalingGroups[*].[AutoScalingGroupName,DesiredCapacity]" \
  --output table \
  --region us-east-1'

# 3. Verify zero downtime
while true; do
  curl -s -o /dev/null -w "%{http_code}\n" http://dev-jenkins-alb-121130223.us-east-1.elb.amazonaws.com:8080
  sleep 2
done
```

### Test 3: Disaster Recovery
```bash
# 1. Create backup
aws backup start-backup-job \
  --backup-vault-name Default \
  --resource-arn $(terraform output -raw efs_arn) \
  --iam-role-arn $(terraform output -raw backup_role_arn) \
  --region us-east-1

# 2. Deploy to DR region
cd environments/dev-dr
terraform init
terraform plan -var="region=us-west-2"
terraform apply -auto-approve

# 3. Restore from backup
aws backup start-restore-job \
  --recovery-point-arn <backup-arn> \
  --region us-west-2
```

### Test 4: Auto Scaling
```bash
# 1. Generate load
ab -n 10000 -c 100 http://dev-jenkins-alb-121130223.us-east-1.elb.amazonaws.com:8080/

# 2. Monitor scaling
watch -n 10 'aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names dev-jenkins-enterprise-platform-asg \
  --query "AutoScalingGroups[0].[DesiredCapacity,Instances[*].InstanceId]" \
  --region us-east-1'

# 3. Check CloudWatch alarms
aws cloudwatch describe-alarms \
  --alarm-names dev-jenkins-high-cpu \
  --region us-east-1
```

---

## Performance Testing

### Load Testing
```bash
# Install Apache Bench
sudo apt-get install apache2-utils

# Test 1: Basic load
ab -n 1000 -c 10 http://dev-jenkins-alb-121130223.us-east-1.elb.amazonaws.com:8080/

# Test 2: Sustained load
ab -n 10000 -c 50 -t 300 http://dev-jenkins-alb-121130223.us-east-1.elb.amazonaws.com:8080/

# Test 3: Spike test
ab -n 5000 -c 200 http://dev-jenkins-alb-121130223.us-east-1.elb.amazonaws.com:8080/
```

### Response Time Testing
```bash
# Test ALB response time
for i in {1..100}; do
  curl -o /dev/null -s -w "Time: %{time_total}s\n" \
    http://dev-jenkins-alb-121130223.us-east-1.elb.amazonaws.com:8080
done | awk '{sum+=$2; count++} END {print "Average:", sum/count, "seconds"}'
```

---

## Security Testing

### Vulnerability Scanning
```bash
# 1. TFSec scan
docker run --rm -v $(pwd):/src aquasec/tfsec /src

# 2. Trivy scan
trivy fs --severity HIGH,CRITICAL .

# 3. Checkov scan
docker run --rm -v $(pwd):/tf bridgecrew/checkov -d /tf

# 4. GitLeaks scan
docker run --rm -v $(pwd):/path zricethezav/gitleaks:latest detect --source="/path" -v
```

### Penetration Testing
```bash
# 1. Port scanning (authorized only)
nmap -sV dev-jenkins-alb-121130223.us-east-1.elb.amazonaws.com

# 2. SSL/TLS testing
sslscan dev-jenkins-alb-121130223.us-east-1.elb.amazonaws.com:443

# 3. Security headers
curl -I http://dev-jenkins-alb-121130223.us-east-1.elb.amazonaws.com:8080
```

---

## Automated Test Script

See `scripts/test-platform.sh` for automated testing of all components.

**Usage**:
```bash
# Test everything
./scripts/test-platform.sh

# Test specific component
./scripts/test-platform.sh --component vpc
./scripts/test-platform.sh --component jenkins
./scripts/test-platform.sh --component blue-green

# Generate report
./scripts/test-platform.sh --report
```

---

## Success Criteria

### Infrastructure
- ✅ All AWS resources created successfully
- ✅ VPC with 6 subnets across 3 AZs
- ✅ Single NAT Gateway operational
- ✅ Security groups configured correctly
- ✅ EFS mounted on all instances

### Application
- ✅ Jenkins accessible via ALB
- ✅ Jenkins service running
- ✅ Plugins installed
- ✅ Admin password retrievable
- ✅ API responding

### High Availability
- ✅ Multi-AZ deployment
- ✅ Auto Scaling configured
- ✅ Health checks passing
- ✅ Target group healthy
- ✅ Blue-green ASGs configured

### Monitoring
- ✅ CloudWatch dashboard created
- ✅ Alarms configured and active
- ✅ Log groups receiving logs
- ✅ Metrics being collected
- ✅ SNS notifications working

### Security
- ✅ All volumes encrypted
- ✅ VPC Flow Logs enabled
- ✅ IAM roles least privilege
- ✅ Security groups restrictive
- ✅ No critical vulnerabilities

### Cost Optimization
- ✅ All resources tagged
- ✅ Single NAT Gateway
- ✅ Lifecycle policies configured
- ✅ Auto Scaling for cost savings

---

## Troubleshooting Common Issues

### Issue: Jenkins not accessible
```bash
# Check ALB
aws elbv2 describe-load-balancers --names dev-jenkins-alb --region us-east-1

# Check target health
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw target_group_arn) \
  --region us-east-1

# Check security groups
aws ec2 describe-security-groups \
  --filters "Name=tag:Environment,Values=dev" \
  --region us-east-1
```

### Issue: EFS not mounted
```bash
# Check EFS status
aws efs describe-file-systems --region us-east-1

# Check mount targets
aws efs describe-mount-targets \
  --file-system-id $(terraform output -raw efs_id) \
  --region us-east-1

# Check instance logs
aws ssm send-command \
  --instance-ids <instance-id> \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["tail -100 /var/log/cloud-init-output.log"]' \
  --region us-east-1
```

### Issue: Blue-green deployment stuck
```bash
# Check Lambda logs
aws logs tail /aws/lambda/jenkins-enterprise-platform-dev-deployment-orchestrator \
  --since 1h \
  --region us-east-1

# Check ASG status
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names \
    jenkins-enterprise-platform-dev-blue-asg \
    jenkins-enterprise-platform-dev-green-asg \
  --region us-east-1

# Manual rollback
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name jenkins-enterprise-platform-dev-green-asg \
  --desired-capacity 0 \
  --region us-east-1
```

---

**Last Updated**: October 24, 2025  
**Version**: 1.0
