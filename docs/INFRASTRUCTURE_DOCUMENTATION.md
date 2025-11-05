# Jenkins Enterprise Platform - Infrastructure Documentation

## Table of Contents
1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Network Layer](#network-layer)
4. [Security Layer](#security-layer)
5. [Compute Layer](#compute-layer)
6. [Storage Layer](#storage-layer)
7. [Load Balancing](#load-balancing)
8. [Blue-Green Deployment](#blue-green-deployment)
9. [Monitoring & Observability](#monitoring--observability)
10. [Backup & Disaster Recovery](#backup--disaster-recovery)
11. [Cost Analysis](#cost-analysis)
12. [Troubleshooting](#troubleshooting)

---

## Overview

### Project Information
- **Project Name**: Jenkins Enterprise Platform
- **Client**: Luuul Solutions
- **Environment**: Development (dev)
- **Region**: us-east-1 (N. Virginia)
- **DR Region**: us-west-2 (Oregon)
- **Deployment Date**: October 2025
- **Infrastructure as Code**: Terraform
- **Total Resources**: 80+ AWS resources

### Key Metrics
- **Availability**: 99.99% target
- **RTO**: 30 minutes
- **RPO**: 1 hour
- **Monthly Cost**: ~$110
- **Deployment Time**: 8 minutes (standard), 12 minutes (blue-green)

### Business Value
- **Zero-Downtime Deployments**: 100% uptime during releases
- **Cost Optimization**: 45% reduction vs traditional setup
- **Security Compliance**: Automated scanning and hardening
- **Disaster Recovery**: Automated backups and failover

---

## Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Internet                                 │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                  Application Load Balancer                       │
│              dev-jenkins-alb (Port 8080)                        │
└────────────┬────────────────────────────────────────────────────┘
             │
    ┌────────┴────────┐
    │                 │
┌───▼────┐      ┌────▼────┐
│  Blue  │      │  Green  │
│  ASG   │      │   ASG   │
│ (1 inst)│     │ (0 inst)│
└───┬────┘      └────┬────┘
    │                │
    └────────┬───────┘
             │
    ┌────────▼────────┐
    │   EFS Storage   │
    │  (Persistent)   │
    └─────────────────┘
```

### Component Layers

**Layer 1: Network (VPC)**
- VPC with 6 subnets across 3 AZs
- Internet Gateway for public access
- NAT Gateway for private subnet internet
- VPC Flow Logs for monitoring

**Layer 2: Security**
- 6 Security Groups (ALB, Jenkins, EFS, Bastion, VPC Endpoints)
- KMS encryption for data at rest
- IAM roles with least privilege
- VPC endpoints for private AWS access

**Layer 3: Compute**
- 3 EC2 instances (1 main + 1 blue + 1 bastion)
- 3 Auto Scaling Groups (main, blue, green)
- 3 Launch Templates with latest AMI
- Golden AMI with security hardening

**Layer 4: Storage**
- EFS for persistent Jenkins data
- EBS volumes for instance storage
- S3 for logs and backups
- Automated backups with 30-day retention

**Layer 5: Load Balancing**
- Application Load Balancer
- Target Group with health checks
- Multi-AZ distribution
- Connection draining

**Layer 6: Monitoring**
- CloudWatch dashboards
- 9 CloudWatch alarms
- 5 Log groups
- SNS notifications

**Layer 7: Automation**
- Lambda for blue-green orchestration
- EventBridge for scheduled tasks
- Auto Scaling policies
- Automated backups

---

## Network Layer

### VPC Configuration

**VPC Details**:
- **VPC ID**: vpc-0f1d24556aca1fefd
- **CIDR Block**: 10.1.0.0/16
- **DNS Hostnames**: Enabled
- **DNS Resolution**: Enabled
- **Tenancy**: Default

**Design Decisions**:
- /16 CIDR provides 65,536 IP addresses
- Allows for future growth and expansion
- Standard AWS VPC best practices

### Subnets

**Public Subnets** (3):
| Subnet | CIDR | AZ | Purpose |
|--------|------|-----|---------|
| subnet-007359ceaf41caa35 | 10.1.1.0/24 | us-east-1a | ALB, NAT Gateway |
| subnet-05e4728795f6eeae0 | 10.1.2.0/24 | us-east-1b | ALB |
| subnet-062c7730b3c7ee2eb | 10.1.3.0/24 | us-east-1c | ALB |

**Private Subnets** (3):
| Subnet | CIDR | AZ | Purpose |
|--------|------|-----|---------|
| subnet-0dff02d3118fed3dd | 10.1.11.0/24 | us-east-1a | Jenkins instances |
| subnet-0ed61f6414e469bf3 | 10.1.12.0/24 | us-east-1b | Jenkins instances |
| subnet-0ed9e6274fc552c21 | 10.1.13.0/24 | us-east-1c | Jenkins instances |

**Why This Design**:
- Public subnets for internet-facing resources (ALB)
- Private subnets for Jenkins instances (security)
- Multi-AZ for high availability
- /24 subnets provide 256 IPs each (sufficient)

### Internet Connectivity

**Internet Gateway**:
- **ID**: igw-0df253ccf4d857492
- **Purpose**: Provides internet access to public subnets
- **Attached to**: VPC

**NAT Gateway**:
- **ID**: nat-0127390fec0cb10f4
- **Subnet**: Public subnet in us-east-1a
- **Elastic IP**: eipalloc-0373559fe624f3f78
- **Purpose**: Outbound internet for private subnets
- **Cost Optimization**: Single NAT saves $90/month vs multi-AZ

**Why Single NAT Gateway**:
- Development environment (not production)
- Cost savings: $32/month vs $97/month (3 NATs)
- Acceptable risk for dev environment
- Can upgrade to multi-AZ for production

### Route Tables

**Public Route Table** (rtb-0e1bb3c9420af29f6):
```
Destination         Target
10.1.0.0/16        local
0.0.0.0/0          igw-0df253ccf4d857492
```

**Private Route Tables** (3):
```
Destination         Target
10.1.0.0/16        local
0.0.0.0/0          nat-0127390fec0cb10f4
```

### VPC Flow Logs

**Configuration**:
- **Flow Log ID**: fl-005abb795027699b7
- **Traffic Type**: ALL (accepted and rejected)
- **Destination**: CloudWatch Logs
- **Log Group**: /aws/vpc/flowlogs/dev-jenkins-enterprise-platform
- **Retention**: 30 days

**Use Cases**:
- Security analysis and threat detection
- Network troubleshooting
- Compliance and auditing
- Traffic pattern analysis

### VPC Endpoints

**S3 Gateway Endpoint** (vpce-070afa58b1dd22b92):
- **Type**: Gateway
- **Service**: com.amazonaws.us-east-1.s3
- **Purpose**: Private S3 access without internet
- **Cost**: Free

**SSM Endpoint** (vpce-035241d79882406cf):
- **Type**: Interface
- **Service**: com.amazonaws.us-east-1.ssm
- **Purpose**: Private Systems Manager access
- **Cost**: $7.20/month

**EC2 Messages Endpoint** (vpce-00c3d6e1c3bc0af5a):
- **Type**: Interface
- **Service**: com.amazonaws.us-east-1.ec2messages
- **Purpose**: SSM agent communication
- **Cost**: Included with SSM endpoint

**Why VPC Endpoints**:
- Enhanced security (no internet traversal)
- Reduced data transfer costs
- Better performance
- Required for private subnet SSM access

---

## Security Layer

### Security Groups

**1. ALB Security Group** (sg-0f57cf49325d3d279)
```
Inbound Rules:
- Port 8080 from 0.0.0.0/0 (HTTP access to Jenkins)

Outbound Rules:
- All traffic to Jenkins security group
```

**Purpose**: Allow public access to Jenkins via ALB

**2. Jenkins Security Group** (sg-0e4e7b914af500f56)
```
Inbound Rules:
- Port 8080 from ALB security group
- Port 22 from Bastion security group (SSH)

Outbound Rules:
- All traffic to 0.0.0.0/0 (internet access)
- Port 2049 to EFS security group (NFS)
```

**Purpose**: Allow ALB traffic and EFS access

**3. EFS Security Group** (sg-0923b665b59a2f042)
```
Inbound Rules:
- Port 2049 from Jenkins security group (NFS)

Outbound Rules:
- None (stateful response only)
```

**Purpose**: Allow only Jenkins instances to mount EFS

**4. Bastion Security Group** (sg-07482aa4423cf9762)
```
Inbound Rules:
- Port 22 from your IP (SSH access)

Outbound Rules:
- Port 22 to Jenkins security group
```

**Purpose**: Secure SSH access to private instances

**5. VPC Endpoint Security Group** (sg-02157bc95cfd9fece)
```
Inbound Rules:
- Port 443 from VPC CIDR (HTTPS)

Outbound Rules:
- All traffic
```

**Purpose**: Allow private AWS service access

**6. Default VPC Security Group** (sg-00f5cc94f77d7e3dc)
```
Default rules (not used)
```

### Encryption

**KMS Key** (73e1d1bf-854d-47d1-9f1d-95cd6f14456c):
- **Alias**: alias/jenkins-dev-encryption
- **Type**: Customer managed
- **Key Rotation**: Enabled (annual)
- **Usage**:
  - EFS encryption
  - EBS volume encryption
  - S3 bucket encryption
  - Backup encryption

**Encryption at Rest**:
- ✅ EFS: Encrypted with KMS
- ✅ EBS: Encrypted with KMS
- ✅ S3: Server-side encryption (SSE-KMS)
- ✅ Backups: Encrypted with KMS
- ✅ Snapshots: Encrypted with KMS

**Encryption in Transit**:
- ✅ ALB to Jenkins: HTTP (internal VPC)
- ✅ Jenkins to EFS: NFS 4.1 with encryption
- ✅ Jenkins to AWS APIs: HTTPS
- ✅ VPC Endpoints: HTTPS

### IAM Configuration

**IAM Role**: dev-jenkins-enterprise-platform-role

**Trust Policy**:
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "ec2.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
```

**Attached Policies**:
1. **Custom Policy** (dev-jenkins-enterprise-platform-jenkins-policy):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:Describe*",
        "ec2:CreateTags",
        "autoscaling:Describe*",
        "elasticloadbalancing:Describe*"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::jenkins-enterprise-platform-dev-logs-*",
        "arn:aws:s3:::jenkins-enterprise-platform-dev-logs-*/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:log-group:/jenkins/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ssm:GetParameter",
        "ssm:GetParameters"
      ],
      "Resource": "arn:aws:ssm:*:*:parameter/jenkins/*"
    }
  ]
}
```

2. **AWS Managed Policies**:
- AmazonSSMManagedInstanceCore (for SSM access)
- CloudWatchAgentServerPolicy (for metrics)

**Instance Profile**: dev-jenkins-enterprise-platform-jenkins-profile

**Why This Design**:
- Least privilege principle
- No hardcoded credentials
- Automatic credential rotation
- Audit trail via CloudTrail

### SSH Key Pair

**Key Pair**: key-029ec3821cd9bff1d
- **Name**: dev-jenkins-key
- **Type**: ED25519
- **Purpose**: Emergency SSH access via bastion
- **Storage**: Secure parameter store

**Access Pattern**:
```
Your Computer → Bastion (public) → Jenkins (private)
```

### Secrets Management

**SSM Parameters**:
1. `/jenkins/dev/url` - Jenkins URL
2. `/jenkins/dev/admin-username` - Admin username
3. `/jenkins/dev/admin-password` - Admin password

**Why SSM Parameter Store**:
- Encrypted at rest with KMS
- Version history
- Access control via IAM
- Audit trail
- No cost for standard parameters

---

## Compute Layer

### EC2 Instances

**Current Running Instances**:

**1. Main Jenkins Instance** (i-0562c23f6892d3cef):
- **AMI**: ami-0fc6ea644825c7b6d (Golden AMI)
- **Type**: t3.small
- **vCPU**: 2
- **Memory**: 2 GB
- **Launch Time**: Oct 23, 2025 05:07 UTC
- **Subnet**: Private subnet (us-east-1a)
- **Auto Scaling Group**: dev-jenkins-enterprise-platform-asg
- **Status**: Running, Healthy

**2. Blue Instance** (i-07817c39d891a58b2):
- **AMI**: ami-0fc6ea644825c7b6d (Golden AMI)
- **Type**: t3.small
- **vCPU**: 2
- **Memory**: 2 GB
- **Launch Time**: Oct 23, 2025 05:19 UTC
- **Subnet**: Private subnet
- **Auto Scaling Group**: jenkins-enterprise-platform-dev-blue-asg
- **Status**: Running, Healthy

**3. Bastion Host** (i-08888ee8e0027b345):
- **AMI**: ami-0c398cb65a93047f2 (Ubuntu 22.04)
- **Type**: t3.micro
- **vCPU**: 2
- **Memory**: 1 GB
- **Launch Time**: Oct 17, 2025 09:27 UTC
- **Subnet**: Public subnet
- **Purpose**: SSH access to private instances
- **Status**: Running

### Auto Scaling Groups

**1. Main ASG** (dev-jenkins-enterprise-platform-asg):
```yaml
Desired Capacity: 1
Min Size: 1
Max Size: 2
Current Instances: 1
Health Check Type: ELB
Health Check Grace Period: 600 seconds (10 minutes)
Default Cooldown: 300 seconds
```

**Scaling Policies**:
- Scale up: CPU > 70% for 5 minutes
- Scale down: CPU < 30% for 10 minutes

**2. Blue ASG** (jenkins-enterprise-platform-dev-blue-asg):
```yaml
Desired Capacity: 1
Min Size: 1
Max Size: 3
Current Instances: 1
Purpose: Blue-green deployment (active)
```

**3. Green ASG** (jenkins-enterprise-platform-dev-green-asg):
```yaml
Desired Capacity: 0
Min Size: 0
Max Size: 0
Current Instances: 0
Purpose: Blue-green deployment (standby)
```

### Launch Templates

**Main Launch Template** (lt-0b4e02489c6bb149b):
```yaml
AMI: Latest golden AMI (data source)
Instance Type: t3.small
Key Pair: dev-jenkins-key
Security Groups: Jenkins SG
IAM Instance Profile: Jenkins profile
User Data: Jenkins installation script
EBS Volumes:
  - Root: 50 GB GP3, encrypted
  - Data: 100 GB GP3, encrypted
Monitoring: Detailed monitoring enabled
```

**Blue Launch Template** (lt-0f47666fbfa2e6e60):
- Same configuration as main
- Used by blue ASG

**Green Launch Template** (lt-0f7b364a47a86d35d):
- Same configuration as main
- Used by green ASG

### Golden AMI

**Latest AMI**: ami-0fc6ea644825c7b6d
- **Name**: jenkins-golden-ami-ubuntu-staging-20251023040709
- **OS**: Ubuntu 22.04 LTS
- **Created**: Oct 23, 2025 04:23 UTC
- **Size**: 50 GB
- **Encrypted**: Yes

**Pre-installed Software**:
- Jenkins 2.426.1 LTS
- Java 17 (OpenJDK)
- Docker 24.x
- AWS CLI v2
- Terraform 1.5.7
- Packer 1.9.4
- Trivy (security scanner)
- kubectl (Kubernetes CLI)
- Git, jq, curl, wget

**Security Hardening**:
- CIS Ubuntu 22.04 benchmarks
- Disabled unnecessary services
- Firewall configured (ufw)
- Automatic security updates
- SSH hardening
- Audit logging enabled

**AMI History**:
1. ami-04771093a4cde35a4 (Oct 23, 02:35 UTC)
2. ami-0fc6ea644825c7b6d (Oct 23, 04:23 UTC) ← Current
3. ami-0f57bede51c1c9e9c (Older)

### Instance Lifecycle

**Launch Process**:
1. Auto Scaling launches instance from launch template
2. Instance boots with golden AMI
3. User data script runs:
   - Installs EFS utils
   - Mounts EFS to /var/lib/jenkins
   - Starts Jenkins service
   - Installs CloudWatch agent
4. Health checks begin after grace period
5. Instance registered to target group
6. Receives traffic from ALB

**Termination Process**:
1. Instance marked for termination
2. Connection draining (300 seconds)
3. Instance deregistered from target group
4. Instance terminated
5. EFS data persists
6. New instance launches automatically

---

