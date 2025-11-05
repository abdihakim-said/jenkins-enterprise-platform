# Jenkins Enterprise Platform - Infrastructure Documentation (Part 2)

## Storage Layer

### EFS (Elastic File System)

**File System Details**:
- **File System ID**: fs-0390b98f1c880f624
- **Name**: dev-jenkins-enterprise-platform-efs
- **Performance Mode**: General Purpose
- **Throughput Mode**: Bursting
- **Encryption**: Enabled (KMS)
- **Lifecycle Management**: Enabled (30 days to IA)
- **Size**: ~10 GB (grows automatically)

**Mount Targets** (3 - Multi-AZ):
| AZ | Subnet | IP Address | Status |
|----|--------|------------|--------|
| us-east-1a | subnet-0dff02d3118fed3dd | 10.1.11.x | Available |
| us-east-1b | subnet-0ed61f6414e469bf3 | 10.1.12.x | Available |
| us-east-1c | subnet-0ed9e6274fc552c21 | 10.1.13.x | Available |

**Access Points** (2):
1. **fsap-0d3b5b40f354f4bb9**: Jenkins data access
2. **fsap-09bbc067252dafab4**: Backup access

**Mount Configuration**:
```bash
# Mount command on instances
mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 \
  fs-0390b98f1c880f624.efs.us-east-1.amazonaws.com:/ /var/lib/jenkins
```

**Directory Structure**:
```
/var/lib/jenkins/
├── config.xml              # Jenkins configuration
├── jobs/                   # Job definitions
├── plugins/                # Installed plugins
├── users/                  # User accounts
├── secrets/                # Credentials
├── workspace/              # Build workspaces
├── logs/                   # Jenkins logs
└── .ssh/                   # SSH keys
```

**Why EFS**:
- **Persistence**: Data survives instance termination
- **Shared Access**: Multiple instances can mount simultaneously
- **Automatic Scaling**: No capacity planning needed
- **Multi-AZ**: Built-in redundancy
- **Backup Integration**: AWS Backup support

**Performance**:
- **Baseline Throughput**: 50 MB/s per TB
- **Burst Throughput**: 100 MB/s
- **IOPS**: Thousands per second
- **Latency**: Single-digit milliseconds

**Cost Optimization**:
- Lifecycle policy moves infrequent files to IA storage
- IA storage costs 85% less than standard
- Automatic tiering based on access patterns

### EBS Volumes

**Root Volumes** (per instance):
- **Type**: GP3 (General Purpose SSD)
- **Size**: 50 GB
- **IOPS**: 3,000 (baseline)
- **Throughput**: 125 MB/s
- **Encryption**: Yes (KMS)
- **Delete on Termination**: Yes

**Why GP3**:
- 20% cheaper than GP2
- Predictable performance
- Independent IOPS and throughput
- Better price-performance ratio

**Snapshots** (4):
- Automated snapshots for AMI creation
- Encrypted with same KMS key
- Stored in S3 (managed by AWS)
- Used for disaster recovery

### S3 Buckets

**1. ALB Logs Bucket** (dev-jenkins-alb-logs-0inc3vi3):
```yaml
Purpose: Store ALB access logs
Versioning: Disabled
Encryption: SSE-S3
Lifecycle:
  - Transition to IA: 30 days
  - Transition to Glacier: 90 days
  - Expiration: 365 days
Public Access: Blocked
Size: ~5 GB/month
Cost: ~$0.12/month
```

**2. Application Logs Bucket** (jenkins-enterprise-platform-dev-logs-84d76e3c):
```yaml
Purpose: Store Jenkins application logs
Versioning: Enabled
Encryption: SSE-KMS
Lifecycle:
  - Transition to IA: 30 days
  - Transition to Glacier: 90 days
  - Expiration: 365 days
Public Access: Blocked
Size: ~10 GB/month
Cost: ~$0.23/month
```

**Lifecycle Policy Benefits**:
- Standard (0-30 days): $0.023/GB
- Standard-IA (30-90 days): $0.0125/GB (46% savings)
- Glacier (90-365 days): $0.004/GB (83% savings)
- **Total Savings**: ~60% on storage costs

---

## Load Balancing

### Application Load Balancer

**ALB Details**:
- **Name**: dev-jenkins-alb
- **ARN**: arn:aws:elasticloadbalancing:us-east-1:...:loadbalancer/app/dev-jenkins-alb/b17c3ab3ca70d81e
- **DNS Name**: dev-jenkins-alb-121130223.us-east-1.elb.amazonaws.com
- **Scheme**: Internet-facing
- **IP Address Type**: IPv4
- **Subnets**: 3 public subnets (Multi-AZ)
- **Security Group**: sg-0f57cf49325d3d279

**Configuration**:
```yaml
Idle Timeout: 60 seconds
Connection Draining: 300 seconds (5 minutes)
Cross-Zone Load Balancing: Enabled
Deletion Protection: Disabled (dev environment)
Access Logs: Enabled → S3
```

**Why ALB**:
- Layer 7 (HTTP/HTTPS) load balancing
- Path-based routing capability
- Health checks at application level
- WebSocket support (for Jenkins)
- Integration with Auto Scaling
- Free SSL/TLS termination

### Target Group

**Target Group Details**:
- **Name**: dev-jenkins-tg
- **ARN**: arn:aws:elasticloadbalancing:us-east-1:...:targetgroup/dev-jenkins-tg/d888843a89f785e1
- **Protocol**: HTTP
- **Port**: 8080
- **VPC**: vpc-0f1d24556aca1fefd
- **Target Type**: Instance

**Health Check Configuration**:
```yaml
Protocol: HTTP
Port: 8080
Path: /login
Interval: 30 seconds
Timeout: 5 seconds
Healthy Threshold: 2 consecutive successes
Unhealthy Threshold: 2 consecutive failures
Success Codes: 200,403
```

**Why /login Path**:
- Always accessible (no auth required)
- Returns 200 or 403 (both indicate Jenkins is running)
- Faster than checking root path
- Reliable health indicator

**Current Targets**:
| Instance ID | AZ | Health Status | Reason |
|-------------|-----|---------------|--------|
| i-0562c23f6892d3cef | us-east-1a | Healthy | N/A |
| i-07817c39d891a58b2 | us-east-1b | Healthy | N/A |

**Target Registration**:
- Automatic via Auto Scaling Group
- Deregistration delay: 300 seconds
- Connection draining during deregistration

### Listeners

**Listener 1** (870cfce693824613):
```yaml
Protocol: HTTP
Port: 8080
Default Action: Forward to dev-jenkins-tg
Rules: None (simple forward)
```

**Listener 2** (179951787cb76f0d):
```yaml
Protocol: HTTP
Port: 80
Default Action: Redirect to port 8080
Rules: None
```

**Why Port 8080**:
- Jenkins default port
- Avoids conflict with system services
- Common for Java applications
- Easy to remember

### Traffic Flow

```
User Request
    ↓
Internet Gateway
    ↓
ALB (Public Subnets)
    ↓
Target Group Health Check
    ↓
Round Robin Distribution
    ↓
Jenkins Instance (Private Subnet)
    ↓
EFS Mount (Shared Data)
    ↓
Response back through ALB
```

**Load Balancing Algorithm**:
- Round robin by default
- Least outstanding requests (optional)
- Sticky sessions disabled (stateless)

---

## Blue-Green Deployment

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Application Load Balancer                 │
└────────────────────┬────────────────────────────────────────┘
                     │
        ┌────────────┴────────────┐
        │                         │
┌───────▼────────┐       ┌───────▼────────┐
│   Blue ASG     │       │   Green ASG    │
│   (Active)     │       │   (Standby)    │
│   1 instance   │       │   0 instances  │
└────────────────┘       └────────────────┘
        │                         │
        └────────────┬────────────┘
                     │
        ┌────────────▼────────────┐
        │   Shared Infrastructure  │
        │   • EFS (Jenkins data)   │
        │   • VPC & Subnets        │
        │   • Security Groups      │
        └──────────────────────────┘
                     │
        ┌────────────▼────────────┐
        │  Lambda Orchestrator    │
        │  (Automated switching)  │
        └──────────────────────────┘
                     │
        ┌────────────▼────────────┐
        │   EventBridge Rule      │
        │   (Every 5 minutes)     │
        └──────────────────────────┘
```

### Lambda Orchestrator

**Function 1**: jenkins-enterprise-platform-dev-deployment-orchestrator
```yaml
Runtime: Python 3.9
Memory: 256 MB
Timeout: 300 seconds (5 minutes)
Handler: lambda_function.lambda_handler
Environment Variables:
  - BLUE_ASG_NAME: jenkins-enterprise-platform-dev-blue-asg
  - GREEN_ASG_NAME: jenkins-enterprise-platform-dev-green-asg
  - TARGET_GROUP_ARN: arn:aws:elasticloadbalancing:...
  - SNS_TOPIC_ARN: arn:aws:sns:...
```

**Orchestration Logic**:
```python
def lambda_handler(event, context):
    # 1. Determine current active deployment
    active_color = get_active_deployment()
    new_color = 'green' if active_color == 'blue' else 'blue'
    
    # 2. Scale up new environment
    scale_asg(new_color, desired_capacity=1)
    wait_for_healthy_instances(new_color, timeout=600)
    
    # 3. Validate health checks
    if not validate_health(new_color, checks=5):
        rollback(active_color)
        send_notification("Deployment failed - rolled back")
        return {'status': 'failed', 'reason': 'health_check_failed'}
    
    # 4. Switch traffic
    switch_traffic_to(new_color)
    wait_for_connection_draining(300)
    
    # 5. Scale down old environment
    scale_asg(active_color, desired_capacity=0)
    
    # 6. Send success notification
    send_notification(f"Deployment successful - switched to {new_color}")
    return {'status': 'success', 'active': new_color}
```

**IAM Permissions**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:SetDesiredCapacity",
        "autoscaling:UpdateAutoScalingGroup"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:DescribeTargetHealth",
        "elasticloadbalancing:DescribeTargetGroups",
        "elasticloadbalancing:ModifyTargetGroup"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": ["sns:Publish"],
      "Resource": "arn:aws:sns:*:*:jenkins-*"
    }
  ]
}
```

### EventBridge Rules

**Rule 1**: jenkins-enterprise-platform-dev-health-check
```yaml
Schedule: rate(5 minutes)
Target: Lambda orchestrator
Enabled: Yes
Purpose: Continuous health monitoring
```

**Rule 2**: dev-jenkins-enterprise-platform-inspector-findings
```yaml
Event Pattern: AWS Inspector findings
Target: SNS topic
Enabled: Yes
Purpose: Security vulnerability alerts
```

### Deployment Process

**Step-by-Step Flow**:

**1. Pre-Deployment** (Current State):
```
Blue ASG: 1 instance (serving traffic)
Green ASG: 0 instances (standby)
ALB: Routes to Blue
```

**2. Trigger Deployment**:
```bash
# Manual trigger
aws lambda invoke \
  --function-name jenkins-enterprise-platform-dev-deployment-orchestrator \
  --region us-east-1 \
  response.json

# Or automatic via EventBridge
```

**3. Scale Up New Environment** (0-2 minutes):
```
Blue ASG: 1 instance (serving traffic)
Green ASG: 1 instance (launching)
ALB: Routes to Blue
Status: Waiting for Green to be healthy
```

**4. Health Validation** (2-5 minutes):
```
Blue ASG: 1 instance (serving traffic)
Green ASG: 1 instance (healthy)
ALB: Routes to Blue
Status: Running health checks on Green
```

**5. Traffic Switch** (5-6 minutes):
```
Blue ASG: 1 instance (draining connections)
Green ASG: 1 instance (receiving traffic)
ALB: Routes to Green
Status: Connection draining (300 seconds)
```

**6. Scale Down Old Environment** (6-8 minutes):
```
Blue ASG: 0 instances (terminated)
Green ASG: 1 instance (serving traffic)
ALB: Routes to Green
Status: Deployment complete
```

**7. Post-Deployment** (Final State):
```
Blue ASG: 0 instances (standby)
Green ASG: 1 instance (serving traffic)
ALB: Routes to Green
Status: Ready for next deployment
```

### Rollback Mechanism

**Automatic Rollback Triggers**:
1. Health check failures (>2 consecutive)
2. Instance launch failures
3. Timeout (>10 minutes)
4. Manual intervention

**Rollback Process**:
```python
def rollback(previous_active):
    # 1. Keep traffic on current active
    log.info(f"Rollback initiated - keeping traffic on {previous_active}")
    
    # 2. Scale down failed new environment
    new_color = 'green' if previous_active == 'blue' else 'blue'
    scale_asg(new_color, desired_capacity=0)
    
    # 3. Ensure old environment is healthy
    validate_health(previous_active)
    
    # 4. Send alert
    send_notification(f"Rollback complete - traffic on {previous_active}")
```

**Rollback Time**: <2 minutes (no traffic switch needed)

### Monitoring Deployment

**CloudWatch Metrics**:
- `DeploymentStatus`: success/failed/in_progress
- `ActiveEnvironment`: blue/green
- `HealthChecksPassed`: count
- `DeploymentDuration`: seconds

**CloudWatch Logs**:
```
/aws/lambda/jenkins-enterprise-platform-dev-deployment-orchestrator
```

**Sample Log Entry**:
```
[INFO] Starting blue-green deployment
[INFO] Current active: blue
[INFO] Scaling up green environment
[INFO] Waiting for healthy instances...
[INFO] Green instance i-xxx is healthy
[INFO] Health validation passed (5/5 checks)
[INFO] Switching traffic to green
[INFO] Connection draining complete
[INFO] Scaling down blue environment
[INFO] Deployment successful in 7m 32s
```

### Cost Analysis

**Normal Operation** (1 environment):
```
EC2 (t3.small): $15.18/month
EFS: $3.00/month
ALB: $16.20/month
Lambda: $0.20/month (minimal invocations)
Total: $34.58/month
```

**During Deployment** (2 environments for ~8 minutes):
```
Additional EC2 cost: $0.02 per deployment
Monthly (4 deployments): $0.08/month
```

**Cost Savings vs Always-On Dual Environment**:
- Dual environment: $30.36/month (2x EC2)
- Blue-green: $15.18/month + $0.08/month
- **Savings**: $15.10/month (50%)

### Best Practices

**1. Pre-Deployment Checklist**:
- [ ] Test new AMI in dev environment
- [ ] Validate Jenkins configuration
- [ ] Run security scans
- [ ] Backup current state
- [ ] Schedule during low-traffic period

**2. During Deployment**:
- [ ] Monitor CloudWatch logs
- [ ] Watch health check status
- [ ] Verify zero downtime
- [ ] Check application functionality

**3. Post-Deployment**:
- [ ] Validate Jenkins is accessible
- [ ] Test job execution
- [ ] Verify EFS mount
- [ ] Check plugin functionality
- [ ] Monitor for 24 hours

**4. Rollback Criteria**:
- Health checks fail >2 times
- Response time >5 seconds
- Error rate >5%
- Manual decision

---

