# 🔧 Jenkins Enterprise Platform - Troubleshooting Guide

## 📋 Table of Contents

- [Common Issues](#common-issues)
- [Infrastructure Issues](#infrastructure-issues)
- [Jenkins Application Issues](#jenkins-application-issues)
- [Network & Connectivity Issues](#network--connectivity-issues)
- [Storage Issues](#storage-issues)
- [Security Issues](#security-issues)
- [Performance Issues](#performance-issues)
- [Monitoring Issues](#monitoring-issues)
- [Deployment Issues](#deployment-issues)
- [Emergency Procedures](#emergency-procedures)

## Common Issues

### 🚨 Jenkins Not Accessible

**Symptoms**: Cannot access Jenkins via load balancer URL

**Diagnosis**:
```bash
# Check load balancer status
aws elbv2 describe-load-balancers --names staging-jenkins-alb

# Check target group health
aws elbv2 describe-target-health --target-group-arn $(terraform output -raw target_group_arn)

# Check Jenkins instance status
aws ec2 describe-instances --filters "Name=tag:Name,Values=*jenkins*" --query 'Reservations[].Instances[].[InstanceId,State.Name,PrivateIpAddress]'
```

**Solutions**:

1. **Instance not healthy**:
   ```bash
   # Check instance logs
   INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=*jenkins*" --query 'Reservations[0].Instances[0].InstanceId' --output text)
   aws logs get-log-events --log-group-name "/jenkins/staging/system" --log-stream-name "$INSTANCE_ID"
   
   # Restart Jenkins service
   aws ssm send-command --instance-ids "$INSTANCE_ID" --document-name "AWS-RunShellScript" --parameters 'commands=["sudo systemctl restart jenkins"]'
   ```

2. **Security group issues**:
   ```bash
   # Check security group rules
   aws ec2 describe-security-groups --group-ids $(terraform output -raw jenkins_security_group_id)
   
   # Add missing rules if needed
   aws ec2 authorize-security-group-ingress --group-id $(terraform output -raw jenkins_security_group_id) --protocol tcp --port 8080 --source-group $(terraform output -raw alb_security_group_id)
   ```

3. **Load balancer configuration**:
   ```bash
   # Check listener configuration
   aws elbv2 describe-listeners --load-balancer-arn $(terraform output -raw load_balancer_arn)
   
   # Check target group configuration
   aws elbv2 describe-target-groups --target-group-arns $(terraform output -raw target_group_arn)
   ```

### 🔄 Auto Scaling Issues

**Symptoms**: Instances not launching or terminating unexpectedly

**Diagnosis**:
```bash
# Check auto scaling group status
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names staging-jenkins-asg-blue

# Check scaling activities
aws autoscaling describe-scaling-activities --auto-scaling-group-name staging-jenkins-asg-blue --max-items 10
```

**Solutions**:

1. **Launch failures**:
   ```bash
   # Check launch template
   aws ec2 describe-launch-templates --launch-template-names staging-jenkins-blue-*
   
   # Verify AMI availability
   aws ec2 describe-images --image-ids $(aws ec2 describe-launch-template-versions --launch-template-name staging-jenkins-blue-* --query 'LaunchTemplateVersions[0].LaunchTemplateData.ImageId' --output text)
   
   # Check instance limits
   aws service-quotas get-service-quota --service-code ec2 --quota-code L-1216C47A
   ```

2. **Capacity issues**:
   ```bash
   # Check available capacity in AZs
   aws ec2 describe-availability-zones --zone-names us-east-1a us-east-1b us-east-1c
   
   # Try different instance type
   terraform apply -var="jenkins_instance_type=t3.small"
   ```

## Infrastructure Issues

### 🏗️ Terraform Deployment Failures

**Common Terraform Errors**:

1. **State Lock Issues**:
   ```bash
   # Force unlock (use with caution)
   terraform force-unlock LOCK_ID
   
   # Or delete lock from DynamoDB if using remote state
   aws dynamodb delete-item --table-name terraform-state-lock --key '{"LockID":{"S":"your-lock-id"}}'
   ```

2. **Resource Already Exists**:
   ```bash
   # Import existing resource
   terraform import aws_vpc.jenkins_vpc vpc-12345678
   
   # Or remove from state and let Terraform recreate
   terraform state rm aws_vpc.jenkins_vpc
   ```

3. **Insufficient Permissions**:
   ```bash
   # Check current permissions
   aws sts get-caller-identity
   aws iam simulate-principal-policy --policy-source-arn $(aws sts get-caller-identity --query Arn --output text) --action-names ec2:CreateVpc --resource-arns "*"
   ```

### 🔧 Resource Limits

**AWS Service Limits**:
```bash
# Check EC2 limits
aws service-quotas list-service-quotas --service-code ec2 --query 'Quotas[?contains(QuotaName, `Running On-Demand`)]'

# Check VPC limits
aws service-quotas list-service-quotas --service-code vpc --query 'Quotas[?contains(QuotaName, `VPCs`)]'

# Request limit increase
aws service-quotas request-service-quota-increase --service-code ec2 --quota-code L-1216C47A --desired-value 100
```

## Jenkins Application Issues

### 🏗️ Jenkins Won't Start

**Diagnosis**:
```bash
# Check Jenkins service status
INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=*jenkins*" --query 'Reservations[0].Instances[0].InstanceId' --output text)

aws ssm send-command --instance-ids "$INSTANCE_ID" --document-name "AWS-RunShellScript" --parameters 'commands=["sudo systemctl status jenkins", "sudo journalctl -u jenkins -n 50"]'
```

**Common Solutions**:

1. **Java Issues**:
   ```bash
   # Check Java version
   aws ssm send-command --instance-ids "$INSTANCE_ID" --document-name "AWS-RunShellScript" --parameters 'commands=["java -version", "which java"]'
   
   # Fix Java path
   aws ssm send-command --instance-ids "$INSTANCE_ID" --document-name "AWS-RunShellScript" --parameters 'commands=["sudo update-alternatives --config java"]'
   ```

2. **Memory Issues**:
   ```bash
   # Check memory usage
   aws ssm send-command --instance-ids "$INSTANCE_ID" --document-name "AWS-RunShellScript" --parameters 'commands=["free -h", "ps aux --sort=-%mem | head -10"]'
   
   # Increase Jenkins heap size
   aws ssm send-command --instance-ids "$INSTANCE_ID" --document-name "AWS-RunShellScript" --parameters 'commands=["sudo sed -i \"s/JAVA_ARGS=\\\"-Xmx.*\\\"/JAVA_ARGS=\\\"-Xmx1g\\\"/\" /etc/default/jenkins", "sudo systemctl restart jenkins"]'
   ```

3. **Permission Issues**:
   ```bash
   # Fix Jenkins home permissions
   aws ssm send-command --instance-ids "$INSTANCE_ID" --document-name "AWS-RunShellScript" --parameters 'commands=["sudo chown -R jenkins:jenkins /var/lib/jenkins", "sudo chmod 755 /var/lib/jenkins"]'
   ```

### 🔌 Plugin Issues

**Plugin Installation Failures**:
```bash
# Check plugin directory permissions
aws ssm send-command --instance-ids "$INSTANCE_ID" --document-name "AWS-RunShellScript" --parameters 'commands=["ls -la /var/lib/jenkins/plugins/", "sudo chown -R jenkins:jenkins /var/lib/jenkins/plugins/"]'

# Clear plugin cache
aws ssm send-command --instance-ids "$INSTANCE_ID" --document-name "AWS-RunShellScript" --parameters 'commands=["sudo rm -rf /var/lib/jenkins/plugins/*.jpi.tmp", "sudo systemctl restart jenkins"]'
```

### 🔐 Authentication Issues

**Lost Admin Password**:
```bash
# Retrieve from SSM Parameter Store
aws ssm get-parameter --name "/jenkins/staging/admin-password" --with-decryption --query 'Parameter.Value' --output text

# Reset admin password
aws ssm send-command --instance-ids "$INSTANCE_ID" --document-name "AWS-RunShellScript" --parameters 'commands=["sudo systemctl stop jenkins", "sudo rm /var/lib/jenkins/secrets/initialAdminPassword", "sudo systemctl start jenkins"]'
```

## Network & Connectivity Issues

### 🌐 VPC Connectivity

**Diagnosis**:
```bash
# Check VPC configuration
aws ec2 describe-vpcs --vpc-ids $(terraform output -raw vpc_id)

# Check route tables
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$(terraform output -raw vpc_id)"

# Check NAT gateways
aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$(terraform output -raw vpc_id)"
```

**Solutions**:

1. **No Internet Access from Private Subnets**:
   ```bash
   # Check NAT gateway status
   aws ec2 describe-nat-gateways --filter "Name=state,Values=available"
   
   # Check route table associations
   aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$(terraform output -raw vpc_id)" --query 'RouteTables[].Associations[]'
   
   # Fix routing
   terraform apply -target=module.networking
   ```

2. **Security Group Issues**:
   ```bash
   # Test connectivity
   aws ssm send-command --instance-ids "$INSTANCE_ID" --document-name "AWS-RunShellScript" --parameters 'commands=["curl -I https://google.com", "nslookup google.com"]'
   
   # Check security group rules
   aws ec2 describe-security-groups --group-ids $(terraform output -raw jenkins_security_group_id) --query 'SecurityGroups[].IpPermissionsEgress'
   ```

### 🔗 VPC Endpoints

**VPC Endpoint Issues**:
```bash
# Check VPC endpoints
aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$(terraform output -raw vpc_id)"

# Test S3 endpoint
aws ssm send-command --instance-ids "$INSTANCE_ID" --document-name "AWS-RunShellScript" --parameters 'commands=["aws s3 ls --region us-east-1"]'

# Test SSM endpoint
aws ssm send-command --instance-ids "$INSTANCE_ID" --document-name "AWS-RunShellScript" --parameters 'commands=["aws ssm get-parameter --name /jenkins/staging/admin-password --region us-east-1"]'
```

## Storage Issues

### 📁 EFS Mount Issues

**Diagnosis**:
```bash
# Check EFS file system
aws efs describe-file-systems --file-system-id $(terraform output -raw efs_id)

# Check mount targets
aws efs describe-mount-targets --file-system-id $(terraform output -raw efs_id)

# Check mount status on instance
aws ssm send-command --instance-ids "$INSTANCE_ID" --document-name "AWS-RunShellScript" --parameters 'commands=["df -h | grep efs", "mount | grep efs", "ls -la /var/lib/jenkins/"]'
```

**Solutions**:

1. **Mount Failures**:
   ```bash
   # Check NFS utilities
   aws ssm send-command --instance-ids "$INSTANCE_ID" --document-name "AWS-RunShellScript" --parameters 'commands=["sudo apt-get update", "sudo apt-get install -y nfs-common"]'
   
   # Manual mount
   EFS_DNS=$(terraform output -raw efs_dns_name)
   aws ssm send-command --instance-ids "$INSTANCE_ID" --document-name "AWS-RunShellScript" --parameters "commands=[\"sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 $EFS_DNS:/ /var/lib/jenkins\"]"
   ```

2. **Permission Issues**:
   ```bash
   # Fix EFS permissions
   aws ssm send-command --instance-ids "$INSTANCE_ID" --document-name "AWS-RunShellScript" --parameters 'commands=["sudo chown jenkins:jenkins /var/lib/jenkins", "sudo chmod 755 /var/lib/jenkins"]'
   ```

3. **Performance Issues**:
   ```bash
   # Check EFS performance mode
   aws efs describe-file-systems --file-system-id $(terraform output -raw efs_id) --query 'FileSystems[0].PerformanceMode'
   
   # Monitor EFS metrics
   aws cloudwatch get-metric-statistics --namespace AWS/EFS --metric-name TotalIOTime --dimensions Name=FileSystemId,Value=$(terraform output -raw efs_id) --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) --end-time $(date -u +%Y-%m-%dT%H:%M:%S) --period 300 --statistics Average
   ```

### 🪣 S3 Backup Issues

**Diagnosis**:
```bash
# Check S3 bucket
aws s3 ls s3://$(terraform output -raw s3_backup_bucket)

# Check bucket policy
aws s3api get-bucket-policy --bucket $(terraform output -raw s3_backup_bucket)

# Test access from instance
aws ssm send-command --instance-ids "$INSTANCE_ID" --document-name "AWS-RunShellScript" --parameters "commands=[\"aws s3 ls s3://$(terraform output -raw s3_backup_bucket)\"]"
```

**Solutions**:

1. **Access Denied**:
   ```bash
   # Check IAM role permissions
   aws iam get-role-policy --role-name staging-jenkins-role --policy-name staging-jenkins-role-policy
   
   # Update IAM policy
   terraform apply -target=module.security
   ```

2. **Lifecycle Policy Issues**:
   ```bash
   # Check lifecycle configuration
   aws s3api get-bucket-lifecycle-configuration --bucket $(terraform output -raw s3_backup_bucket)
   
   # Update lifecycle policy
   terraform apply -target=module.s3_backup
   ```

## Security Issues

### 🔒 Security Group Problems

**Diagnosis**:
```bash
# Check all security groups
aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$(terraform output -raw vpc_id)"

# Test connectivity
aws ssm send-command --instance-ids "$INSTANCE_ID" --document-name "AWS-RunShellScript" --parameters 'commands=["telnet $(terraform output -raw load_balancer_dns) 80"]'
```

**Solutions**:

1. **Blocked Traffic**:
   ```bash
   # Add temporary rule for debugging
   aws ec2 authorize-security-group-ingress --group-id $(terraform output -raw jenkins_security_group_id) --protocol tcp --port 8080 --cidr 0.0.0.0/0
   
   # Remove after debugging
   aws ec2 revoke-security-group-ingress --group-id $(terraform output -raw jenkins_security_group_id) --protocol tcp --port 8080 --cidr 0.0.0.0/0
   ```

### 🔐 IAM Permission Issues

**Diagnosis**:
```bash
# Check current role
aws ssm send-command --instance-ids "$INSTANCE_ID" --document-name "AWS-RunShellScript" --parameters 'commands=["aws sts get-caller-identity"]'

# Test specific permissions
aws ssm send-command --instance-ids "$INSTANCE_ID" --document-name "AWS-RunShellScript" --parameters 'commands=["aws s3 ls", "aws ssm get-parameter --name /test"]'
```

**Solutions**:
```bash
# Update IAM policy
terraform apply -target=module.security

# Attach additional policies if needed
aws iam attach-role-policy --role-name staging-jenkins-role --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy
```

## Performance Issues

### 🐌 Slow Response Times

**Diagnosis**:
```bash
# Check system resources
aws ssm send-command --instance-ids "$INSTANCE_ID" --document-name "AWS-RunShellScript" --parameters 'commands=["top -b -n1", "iostat -x 1 5", "free -h"]'

# Check Jenkins thread dump
aws ssm send-command --instance-ids "$INSTANCE_ID" --document-name "AWS-RunShellScript" --parameters 'commands=["curl -s http://localhost:8080/threadDump"]'
```

**Solutions**:

1. **Scale Up Instance**:
   ```bash
   # Change instance type
   terraform apply -var="jenkins_instance_type=t3.small"
   ```

2. **Optimize Jenkins**:
   ```bash
   # Increase heap size
   aws ssm send-command --instance-ids "$INSTANCE_ID" --document-name "AWS-RunShellScript" --parameters 'commands=["sudo sed -i \"s/-Xmx.*/-Xmx2g/\" /etc/default/jenkins", "sudo systemctl restart jenkins"]'
   
   # Clean up old builds
   aws ssm send-command --instance-ids "$INSTANCE_ID" --document-name "AWS-RunShellScript" --parameters 'commands=["find /var/lib/jenkins/jobs/*/builds/* -type d -mtime +30 -exec rm -rf {} +"]'
   ```

### 📊 High Resource Usage

**Memory Issues**:
```bash
# Check memory usage
aws cloudwatch get-metric-statistics --namespace AWS/EC2 --metric-name MemoryUtilization --dimensions Name=InstanceId,Value=$INSTANCE_ID --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) --end-time $(date -u +%Y-%m-%dT%H:%M:%S) --period 300 --statistics Average

# Scale out if needed
aws autoscaling set-desired-capacity --auto-scaling-group-name staging-jenkins-asg-blue --desired-capacity 2
```

## Monitoring Issues

### 📊 Missing Metrics

**CloudWatch Issues**:
```bash
# Check CloudWatch agent status
aws ssm send-command --instance-ids "$INSTANCE_ID" --document-name "AWS-RunShellScript" --parameters 'commands=["sudo systemctl status amazon-cloudwatch-agent", "sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -a query"]'

# Restart CloudWatch agent
aws ssm send-command --instance-ids "$INSTANCE_ID" --document-name "AWS-RunShellScript" --parameters 'commands=["sudo systemctl restart amazon-cloudwatch-agent"]'
```

### 🚨 Alert Issues

**SNS Notifications Not Working**:
```bash
# Test SNS topic
aws sns publish --topic-arn $(terraform output -raw sns_topic_arn) --message "Test alert from Jenkins platform"

# Check SNS subscriptions
aws sns list-subscriptions-by-topic --topic-arn $(terraform output -raw sns_topic_arn)

# Add email subscription
aws sns subscribe --topic-arn $(terraform output -raw sns_topic_arn) --protocol email --notification-endpoint your-email@company.com
```

## Deployment Issues

### 🚀 Blue-Green Deployment Problems

**Diagnosis**:
```bash
# Check both target groups
aws elbv2 describe-target-health --target-group-arn $(terraform output -raw blue_target_group_arn)
aws elbv2 describe-target-health --target-group-arn $(terraform output -raw green_target_group_arn)

# Check listener rules
aws elbv2 describe-listeners --load-balancer-arn $(terraform output -raw load_balancer_arn)
```

**Solutions**:

1. **Stuck Deployment**:
   ```bash
   # Force traffic switch
   aws elbv2 modify-listener --listener-arn $(terraform output -raw listener_arn) --default-actions Type=forward,TargetGroupArn=$(terraform output -raw blue_target_group_arn)
   
   # Scale down problematic environment
   aws autoscaling update-auto-scaling-group --auto-scaling-group-name staging-jenkins-asg-green --desired-capacity 0
   ```

2. **Health Check Failures**:
   ```bash
   # Adjust health check settings
   aws elbv2 modify-target-group --target-group-arn $(terraform output -raw green_target_group_arn) --health-check-interval-seconds 30 --health-check-timeout-seconds 10 --healthy-threshold-count 2
   ```

## Emergency Procedures

### 🚨 Complete System Failure

**Emergency Recovery Steps**:

1. **Immediate Response**:
   ```bash
   # Check overall system status
   ./scripts/system-health-check.sh
   
   # Scale up if needed
   aws autoscaling set-desired-capacity --auto-scaling-group-name staging-jenkins-asg-blue --desired-capacity 3
   ```

2. **Data Recovery**:
   ```bash
   # Restore from S3 backup
   aws s3 sync s3://$(terraform output -raw s3_backup_bucket)/jenkins-home/ /tmp/jenkins-restore/
   
   # Mount EFS and restore
   sudo mount -t nfs4 $(terraform output -raw efs_dns_name):/ /mnt/efs
   sudo cp -r /tmp/jenkins-restore/* /mnt/efs/
   ```

3. **Disaster Recovery**:
   ```bash
   # Deploy to secondary region
   cd terraform/environments/dr
   terraform apply -auto-approve
   
   # Update DNS to point to DR environment
   aws route53 change-resource-record-sets --hosted-zone-id Z123456789 --change-batch file://dns-failover.json
   ```

### 🔄 Rollback Procedures

**Application Rollback**:
```bash
# Rollback to previous version
./scripts/blue-green-deploy.sh --environment staging --rollback

# Or manual rollback
aws elbv2 modify-listener --listener-arn $(terraform output -raw listener_arn) --default-actions Type=forward,TargetGroupArn=$(terraform output -raw blue_target_group_arn)
```

**Infrastructure Rollback**:
```bash
# Rollback Terraform changes
terraform apply -target=module.auto_scaling_blue -var="jenkins_instance_type=t3.micro"

# Or restore from backup
terraform import aws_instance.jenkins i-1234567890abcdef0
```

## Diagnostic Scripts

### 🔍 System Health Check

Create a comprehensive health check script:

```bash
#!/bin/bash
# system-health-check.sh

echo "=== Jenkins Enterprise Platform Health Check ==="

# Check AWS connectivity
echo "1. AWS Connectivity:"
aws sts get-caller-identity

# Check infrastructure
echo "2. Infrastructure Status:"
terraform output

# Check Jenkins accessibility
echo "3. Jenkins Accessibility:"
JENKINS_URL=$(terraform output -raw jenkins_url)
curl -I $JENKINS_URL/login

# Check EFS
echo "4. EFS Status:"
aws efs describe-file-systems --file-system-id $(terraform output -raw efs_id)

# Check Auto Scaling
echo "5. Auto Scaling Status:"
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names staging-jenkins-asg-blue

# Check CloudWatch Alarms
echo "6. CloudWatch Alarms:"
aws cloudwatch describe-alarms --state-value ALARM

echo "=== Health Check Complete ==="
```

### 📊 Performance Monitoring

```bash
#!/bin/bash
# performance-monitor.sh

INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=*jenkins*" --query 'Reservations[0].Instances[0].InstanceId' --output text)

echo "=== Performance Monitoring ==="

# CPU Usage
aws cloudwatch get-metric-statistics --namespace AWS/EC2 --metric-name CPUUtilization --dimensions Name=InstanceId,Value=$INSTANCE_ID --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) --end-time $(date -u +%Y-%m-%dT%H:%M:%S) --period 300 --statistics Average

# Memory Usage
aws cloudwatch get-metric-statistics --namespace CWAgent --metric-name mem_used_percent --dimensions Name=InstanceId,Value=$INSTANCE_ID --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) --end-time $(date -u +%Y-%m-%dT%H:%M:%S) --period 300 --statistics Average

# Disk Usage
aws cloudwatch get-metric-statistics --namespace CWAgent --metric-name disk_used_percent --dimensions Name=InstanceId,Value=$INSTANCE_ID,Name=device,Value=/dev/xvda1 --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) --end-time $(date -u +%Y-%m-%dT%H:%M:%S) --period 300 --statistics Average

echo "=== Performance Monitoring Complete ==="
```

## Getting Help

### 📞 Support Channels

1. **Documentation**: Check this guide and other docs
2. **Logs**: Always check CloudWatch logs first
3. **Community**: GitHub Issues for community support
4. **AWS Support**: For AWS-specific issues
5. **Emergency**: Follow escalation procedures

### 📝 When Reporting Issues

Include the following information:

1. **Environment**: staging/production
2. **Error Messages**: Exact error messages and logs
3. **Steps to Reproduce**: What actions led to the issue
4. **System State**: Output of health check scripts
5. **Recent Changes**: Any recent deployments or changes

### 🔧 Useful Commands Reference

```bash
# Quick status check
terraform output && aws elbv2 describe-target-health --target-group-arn $(terraform output -raw target_group_arn)

# Emergency scale up
aws autoscaling set-desired-capacity --auto-scaling-group-name staging-jenkins-asg-blue --desired-capacity 3

# Emergency rollback
./scripts/blue-green-deploy.sh --environment staging --rollback

# Check all logs
aws logs describe-log-groups --log-group-name-prefix "/jenkins/staging"

# System resource check
aws ssm send-command --instance-ids "$INSTANCE_ID" --document-name "AWS-RunShellScript" --parameters 'commands=["top -b -n1", "df -h", "free -h"]'
```

---

**Remember**: Always test solutions in a non-production environment first, and maintain regular backups for quick recovery.
