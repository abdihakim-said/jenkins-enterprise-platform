# Jenkins Enterprise Platform - Infrastructure Documentation (Part 3)

## Monitoring & Observability

### CloudWatch Dashboards

**Dashboard Name**: dev-jenkins-enterprise-platform-observability

**Widgets**:

**1. Infrastructure Metrics**:
- CPU Utilization (all instances)
- Memory Utilization
- Disk Usage
- Network In/Out

**2. Application Metrics**:
- Jenkins Job Success Rate
- Jenkins Job Failure Rate
- Active Executors
- Queue Length

**3. Load Balancer Metrics**:
- Request Count
- Target Response Time
- Healthy Host Count
- Unhealthy Host Count
- HTTP 4xx/5xx Errors

**4. Auto Scaling Metrics**:
- Desired Capacity
- In-Service Instances
- Pending Instances
- Terminating Instances

**5. EFS Metrics**:
- Data Read/Write IOPs
- Throughput
- Client Connections
- Burst Credit Balance

### CloudWatch Alarms

**1. High CPU Utilization** (dev-jenkins-high-cpu):
```yaml
Metric: CPUUtilization
Threshold: > 80%
Evaluation Periods: 2
Datapoints to Alarm: 2
Period: 300 seconds (5 minutes)
Statistic: Average
Actions:
  - Send SNS notification
  - Trigger Auto Scaling scale-up
```

**2. High Memory Utilization** (dev-jenkins-high-memory):
```yaml
Metric: MemoryUtilization
Threshold: > 85%
Evaluation Periods: 2
Period: 300 seconds
Actions: SNS notification
```

**3. Unhealthy Target** (dev-jenkins-unhealthy-target):
```yaml
Metric: UnHealthyHostCount
Threshold: >= 1
Evaluation Periods: 2
Period: 60 seconds
Actions:
  - Send SNS notification (critical)
  - Trigger Auto Scaling replacement
```

**4. High Response Time** (dev-jenkins-high-response-time):
```yaml
Metric: TargetResponseTime
Threshold: > 2 seconds
Evaluation Periods: 3
Period: 60 seconds
Actions: SNS notification
```

**5. High Error Rate** (dev-jenkins-high-error-rate):
```yaml
Metric: HTTPCode_Target_5XX_Count
Threshold: > 10 errors
Evaluation Periods: 2
Period: 300 seconds
Actions: SNS notification (critical)
```

**6. EFS Burst Credit Low** (dev-jenkins-efs-burst-credit-low):
```yaml
Metric: BurstCreditBalance
Threshold: < 1000000000000 (1 TB)
Evaluation Periods: 1
Period: 300 seconds
Actions: SNS notification (warning)
```

**7. Auto Scaling Failure** (dev-jenkins-asg-failure):
```yaml
Metric: GroupInServiceInstances
Threshold: < 1
Evaluation Periods: 2
Period: 60 seconds
Actions: SNS notification (critical)
```

**8. Lambda Deployment Failure** (dev-jenkins-lambda-error):
```yaml
Metric: Errors
Namespace: AWS/Lambda
Function: deployment-orchestrator
Threshold: >= 1
Period: 300 seconds
Actions: SNS notification
```

**9. Disk Space Low** (dev-jenkins-disk-space-low):
```yaml
Metric: DiskSpaceUtilization
Threshold: > 80%
Evaluation Periods: 1
Period: 300 seconds
Actions: SNS notification (warning)
```

### CloudWatch Log Groups

**1. Application Logs** (/jenkins/dev/application):
```yaml
Retention: 30 days
Size: ~500 MB/month
Encryption: KMS
Metric Filters:
  - ERROR count
  - WARNING count
  - Job failures
```

**Sample Log Entry**:
```
2025-10-24 01:00:00 INFO  jenkins.InitReactorRunner$1#onAttained: Started initialization
2025-10-24 01:00:05 INFO  jenkins.model.Jenkins#<init>: Jenkins is fully up and running
2025-10-24 01:05:23 INFO  hudson.model.Run#execute: Build #42 started
2025-10-24 01:06:15 INFO  hudson.model.Run#execute: Build #42 completed: SUCCESS
```

**2. System Logs** (/jenkins/dev/system):
```yaml
Retention: 14 days
Size: ~200 MB/month
Content:
  - System messages
  - Service status
  - Package updates
  - Security events
```

**3. User Data Logs** (/jenkins/dev/user-data):
```yaml
Retention: 7 days
Size: ~50 MB/month
Content:
  - Instance initialization
  - EFS mount status
  - Jenkins startup
  - CloudWatch agent installation
```

**4. VPC Flow Logs** (/aws/vpc/flowlogs/dev-jenkins-enterprise-platform):
```yaml
Retention: 30 days
Size: ~1 GB/month
Content:
  - Network traffic
  - Accepted/rejected connections
  - Source/destination IPs
  - Ports and protocols
```

**5. Lambda Logs** (/aws/lambda/jenkins-enterprise-platform-dev-deployment-orchestrator):
```yaml
Retention: 14 days
Size: ~10 MB/month
Content:
  - Deployment events
  - Health check results
  - Errors and warnings
```

### SNS Topics

**1. Observability Alerts** (jenkins-enterprise-platform-dev-observability-alerts):
```yaml
Purpose: General monitoring alerts
Subscriptions:
  - Email: devops-team@example.com
  - Slack: #devops-alerts (via Lambda)
Messages:
  - High CPU/Memory
  - Response time issues
  - EFS performance
```

**2. Deployment Alerts** (jenkins-enterprise-platform-dev-deployment-alerts):
```yaml
Purpose: Blue-green deployment notifications
Subscriptions:
  - Email: devops-team@example.com
Messages:
  - Deployment started
  - Deployment successful
  - Deployment failed
  - Rollback triggered
```

**3. Inspector Notifications** (dev-jenkins-enterprise-platform-inspector-notifications):
```yaml
Purpose: Security vulnerability alerts
Subscriptions:
  - Email: security-team@example.com
Messages:
  - Critical vulnerabilities found
  - High severity findings
  - Compliance violations
```

**4. General Alerts** (dev-jenkins-enterprise-platform-alerts):
```yaml
Purpose: Infrastructure alerts
Subscriptions:
  - Email: devops-team@example.com
Messages:
  - Instance failures
  - Auto Scaling events
  - Backup failures
```

### Metrics Collection

**CloudWatch Agent Configuration**:
```json
{
  "metrics": {
    "namespace": "Jenkins/Dev",
    "metrics_collected": {
      "cpu": {
        "measurement": [
          {"name": "cpu_usage_idle", "rename": "CPU_IDLE"},
          {"name": "cpu_usage_iowait", "rename": "CPU_IOWAIT"}
        ],
        "totalcpu": false
      },
      "disk": {
        "measurement": [
          {"name": "used_percent", "rename": "DISK_USED"}
        ],
        "resources": ["/", "/var/lib/jenkins"]
      },
      "mem": {
        "measurement": [
          {"name": "mem_used_percent", "rename": "MEM_USED"}
        ]
      },
      "netstat": {
        "measurement": [
          {"name": "tcp_established", "rename": "TCP_CONNECTIONS"}
        ]
      }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/jenkins/jenkins.log",
            "log_group_name": "/jenkins/dev/application",
            "log_stream_name": "{instance_id}"
          },
          {
            "file_path": "/var/log/syslog",
            "log_group_name": "/jenkins/dev/system",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
```

### Cost-Optimized Observability

**Monthly Costs**:
```
CloudWatch Metrics (custom): $8/month
CloudWatch Logs (ingestion): $3/month
CloudWatch Alarms (9 alarms): $0.90/month
SNS (notifications): $1/month
S3 (log storage): $2/month
Data Transfer: $1/month
────────────────────────────────
TOTAL: $15.90/month
```

**vs Enterprise ECS Monitoring Stack**:
```
ECS Control Plane: $50/month
Container Insights: $30/month
Enhanced Monitoring: $25/month
Additional Services: $15/month
────────────────────────────────
TOTAL: $120/month

SAVINGS: $104.10/month (87% reduction)
```

---

## Backup & Disaster Recovery

### AWS Backup

**Backup Plan**: jenkins-dev-backup-plan

**Schedule**:
```yaml
Daily Backups:
  Time: 02:00 UTC
  Retention: 30 days
  Lifecycle:
    - Delete after 30 days

Weekly Backups:
  Time: Sunday 03:00 UTC
  Retention: 90 days
  Lifecycle:
    - Transition to cold storage: 30 days
    - Delete after 90 days

Monthly Backups:
  Time: 1st of month 04:00 UTC
  Retention: 365 days
  Lifecycle:
    - Transition to cold storage: 90 days
    - Delete after 365 days
```

**Backup Targets**:
- EFS File System (fs-0390b98f1c880f624)
- EBS Volumes (tagged with Backup=true)

**Current Recovery Points**: 6
- 3 daily backups
- 2 weekly backups
- 1 monthly backup

**Backup Vault**: Default
- Encryption: KMS
- Access Policy: Restricted to backup role
- Cross-region copy: Enabled (us-west-2)

### S3 Backup Strategy

**Configuration Backup**:
```bash
# Automated daily backup script
#!/bin/bash
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BUCKET="jenkins-enterprise-platform-dev-logs-84d76e3c"

# Backup Jenkins configuration
tar -czf /tmp/jenkins-config-${TIMESTAMP}.tar.gz \
  /var/lib/jenkins/config.xml \
  /var/lib/jenkins/jobs/ \
  /var/lib/jenkins/users/ \
  /var/lib/jenkins/secrets/

# Upload to S3
aws s3 cp /tmp/jenkins-config-${TIMESTAMP}.tar.gz \
  s3://${BUCKET}/backups/config/

# Cleanup local file
rm /tmp/jenkins-config-${TIMESTAMP}.tar.gz
```

**Backup Retention**:
```yaml
Standard Storage: 0-30 days
Standard-IA: 30-90 days
Glacier: 90-365 days
Expiration: >365 days
```

### Disaster Recovery Procedures

**RTO (Recovery Time Objective)**: 30 minutes
**RPO (Recovery Point Objective)**: 1 hour

**DR Scenario 1: Single Instance Failure**
```
Detection: <1 minute (health checks)
Auto Scaling launches replacement: 2-3 minutes
Instance initialization: 5-7 minutes
Health checks pass: 2 minutes
Total RTO: ~10 minutes
Data Loss: None (EFS persists)
```

**DR Scenario 2: AZ Failure**
```
Detection: <1 minute
Traffic routes to healthy AZ: Immediate
Auto Scaling launches in healthy AZ: 2-3 minutes
Total RTO: ~5 minutes
Data Loss: None (EFS multi-AZ)
```

**DR Scenario 3: Region Failure**
```
1. Deploy infrastructure in DR region (us-west-2): 15 minutes
   terraform apply -var="region=us-west-2"

2. Restore EFS from backup: 10 minutes
   aws backup start-restore-job \
     --recovery-point-arn <arn> \
     --region us-west-2

3. Update DNS to DR region: 2 minutes

4. Validate functionality: 3 minutes

Total RTO: ~30 minutes
Data Loss: Last 1 hour (RPO)
```

**DR Scenario 4: Complete Data Loss**
```
1. Deploy infrastructure: 15 minutes
2. Restore from S3 backup: 5 minutes
3. Restore EFS from AWS Backup: 10 minutes
4. Validate and test: 5 minutes

Total RTO: ~35 minutes
Data Loss: Last backup (max 24 hours)
```

### Backup Testing

**Quarterly DR Drill**:
```bash
# 1. Create test environment
cd environments/dr-test
terraform apply

# 2. Restore latest backup
aws backup start-restore-job \
  --recovery-point-arn <latest-backup> \
  --region us-east-1

# 3. Validate Jenkins functionality
curl http://dr-test-jenkins-alb.../login
# Login and verify jobs

# 4. Document results
# 5. Destroy test environment
terraform destroy
```

---

## Cost Analysis

### Monthly Cost Breakdown

**Compute** ($30.36/month):
```
EC2 Instances:
  - Main (t3.small): $15.18/month × 1 = $15.18
  - Blue (t3.small): $15.18/month × 1 = $15.18
  - Bastion (t3.micro): $7.59/month × 0.5 = $3.80 (part-time)
  
Subtotal: $34.16/month
```

**Network** ($48.40/month):
```
NAT Gateway:
  - Hourly charge: $0.045 × 730 hours = $32.85
  - Data processing: $0.045/GB × 100 GB = $4.50
  
ALB:
  - Hourly charge: $0.0225 × 730 hours = $16.43
  - LCU charges: ~$5.00
  
Elastic IP: $0.00 (attached to NAT)
Data Transfer: $0.09/GB × 50 GB = $4.50

Subtotal: $63.28/month
```

**Storage** ($8.23/month):
```
EFS:
  - Standard storage: $0.30/GB × 10 GB = $3.00
  - IA storage: $0.025/GB × 5 GB = $0.13
  
EBS:
  - GP3 volumes: $0.08/GB × 50 GB × 2 = $8.00
  
S3:
  - Standard: $0.023/GB × 15 GB = $0.35
  - IA: $0.0125/GB × 10 GB = $0.13
  - Glacier: $0.004/GB × 20 GB = $0.08

Subtotal: $11.69/month
```

**Monitoring** ($15.90/month):
```
CloudWatch:
  - Custom metrics: $0.30 × 20 = $6.00
  - Alarms: $0.10 × 9 = $0.90
  - Logs ingestion: $0.50/GB × 2 GB = $1.00
  - Logs storage: $0.03/GB × 3 GB = $0.09
  
SNS: $0.50/month
S3 (logs): $2.00/month
VPC Flow Logs: $5.00/month

Subtotal: $15.49/month
```

**Backup** ($5.20/month):
```
AWS Backup:
  - EFS snapshots: $0.05/GB × 10 GB = $0.50
  - Storage: $0.05/GB × 30 GB = $1.50
  
S3 Backup:
  - Standard: $0.023/GB × 10 GB = $0.23
  - Glacier: $0.004/GB × 50 GB = $0.20

Subtotal: $2.43/month
```

**Other** ($7.20/month):
```
VPC Endpoints:
  - SSM endpoint: $0.01/hour × 730 = $7.30
  - Data processing: Minimal
  
KMS: $1.00/month
Lambda: $0.20/month

Subtotal: $8.50/month
```

### Total Monthly Cost

```
Compute:     $34.16
Network:     $63.28
Storage:     $11.69
Monitoring:  $15.49
Backup:      $2.43
Other:       $8.50
─────────────────────
TOTAL:       $135.55/month
```

### Cost Optimization Strategies

**Implemented**:
- ✅ Single NAT Gateway (saves $65/month)
- ✅ GP3 instead of GP2 (saves $2/month)
- ✅ EFS Intelligent Tiering (saves $1.50/month)
- ✅ S3 Lifecycle policies (saves $5/month)
- ✅ CloudWatch vs ECS monitoring (saves $105/month)
- ✅ Blue-green standby mode (saves $15/month)

**Total Savings**: $193.50/month (59% reduction)

**Potential Additional Savings**:
- Use Spot Instances for dev: Save $7/month
- Reserved Instances (1-year): Save $30/month
- Reduce log retention: Save $2/month
- Part-time bastion: Save $4/month

---

## Troubleshooting

### Common Issues

**Issue 1: Jenkins Not Accessible**

**Symptoms**:
- HTTP 502/503 errors
- Timeout connecting to Jenkins
- ALB health checks failing

**Diagnosis**:
```bash
# Check target health
aws elbv2 describe-target-health \
  --target-group-arn <tg-arn> \
  --region us-east-1

# Check instance status
aws ec2 describe-instance-status \
  --instance-ids <instance-id> \
  --region us-east-1

# Check Jenkins service
aws ssm send-command \
  --instance-ids <instance-id> \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["systemctl status jenkins"]' \
  --region us-east-1
```

**Resolution**:
1. Check security groups allow port 8080
2. Verify Jenkins service is running
3. Check EFS mount status
4. Review user data logs
5. Restart Jenkins if needed

**Issue 2: EFS Mount Failure**

**Symptoms**:
- Jenkins using local storage
- Data not persisting
- Warning in user data logs

**Diagnosis**:
```bash
# Check EFS status
aws efs describe-file-systems \
  --file-system-id fs-0390b98f1c880f624 \
  --region us-east-1

# Check mount targets
aws efs describe-mount-targets \
  --file-system-id fs-0390b98f1c880f624 \
  --region us-east-1

# Check from instance
aws ssm send-command \
  --instance-ids <instance-id> \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["df -h | grep efs","mount | grep nfs"]' \
  --region us-east-1
```

**Resolution**:
1. Verify EFS security group allows NFS (port 2049)
2. Check nfs-common package installed
3. Verify DNS resolution of EFS endpoint
4. Manual mount attempt
5. Check CloudWatch logs for errors

**Issue 3: High CPU Usage**

**Symptoms**:
- CPU >80% sustained
- Slow Jenkins response
- CloudWatch alarm triggered

**Diagnosis**:
```bash
# Check CPU metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value=<instance-id> \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average \
  --region us-east-1

# Check running processes
aws ssm send-command \
  --instance-ids <instance-id> \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["top -b -n 1 | head -20"]' \
  --region us-east-1
```

**Resolution**:
1. Identify resource-intensive jobs
2. Scale up instance type if needed
3. Optimize Jenkins jobs
4. Add more executors
5. Enable Auto Scaling

**Issue 4: Blue-Green Deployment Failure**

**Symptoms**:
- Lambda timeout
- Deployment stuck
- Automatic rollback

**Diagnosis**:
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
```

**Resolution**:
1. Check health check grace period
2. Verify new instances can reach EFS
3. Check AMI is valid
4. Manual rollback if needed
5. Review Lambda timeout settings

---

**Documentation Version**: 1.0  
**Last Updated**: October 24, 2025  
**Maintained By**: DevOps Team  
**Next Review**: January 2026
