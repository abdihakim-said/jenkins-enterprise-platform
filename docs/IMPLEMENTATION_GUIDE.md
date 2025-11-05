# Jenkins Enterprise Platform - Implementation Guide

## Complete Step-by-Step Deployment

**Time Required**: 45-60 minutes  
**Skill Level**: Intermediate DevOps  
**Cost**: ~$110/month

---

## Prerequisites (10 minutes)

### 1. Install Required Tools

```bash
# macOS
brew install terraform awscli packer jq

# Linux (Ubuntu/Debian)
sudo apt-get update
sudo apt-get install -y unzip jq
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/
wget https://releases.hashicorp.com/packer/1.9.4/packer_1.9.4_linux_amd64.zip
unzip packer_1.9.4_linux_amd64.zip
sudo mv packer /usr/local/bin/
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Verify installations
terraform --version
packer --version
aws --version
```

### 2. Configure AWS Credentials

```bash
# Configure AWS CLI
aws configure
# AWS Access Key ID: [YOUR_ACCESS_KEY]
# AWS Secret Access Key: [YOUR_SECRET_KEY]
# Default region name: us-east-1
# Default output format: json

# Verify credentials
aws sts get-caller-identity

# Expected output:
# {
#     "UserId": "AIDAXXXXXXXXXXXXXXXXX",
#     "Account": "123456789012",
#     "Arn": "arn:aws:iam::123456789012:user/your-user"
# }
```

### 3. Clone Repository

```bash
# Clone the repository
git clone https://github.com/yourusername/jenkins-enterprise-platform.git
cd jenkins-enterprise-platform

# Verify structure
ls -la
```

---

## Phase 1: Golden AMI Creation (15 minutes)

### Step 1: Configure Packer Variables

```bash
cd packer

# Create variables file
cat > variables.auto.pkrvars.hcl <<EOF
aws_region    = "us-east-1"
environment   = "dev"
instance_type = "t3.small"
source_ami_owner = "099720109477"  # Canonical (Ubuntu)
EOF

# Verify Packer configuration
packer validate -var-file=variables.auto.pkrvars.hcl jenkins-ami.pkr.hcl
```

### Step 2: Build Golden AMI

```bash
# Initialize Packer
packer init jenkins-ami.pkr.hcl

# Build AMI (takes ~10-12 minutes)
packer build -var-file=variables.auto.pkrvars.hcl jenkins-ami.pkr.hcl

# Expected output:
# ==> Builds finished. The artifacts of successful builds are:
# --> amazon-ebs.jenkins: AMIs were created:
# us-east-1: ami-0xxxxxxxxxxxxx

# Save AMI ID
export GOLDEN_AMI_ID=$(cat manifest.json | jq -r '.builds[0].artifact_id' | cut -d':' -f2)
echo "Golden AMI ID: $GOLDEN_AMI_ID"
```

### Step 3: Verify AMI

```bash
# Check AMI status
aws ec2 describe-images \
  --image-ids $GOLDEN_AMI_ID \
  --query 'Images[0].[ImageId,Name,State,CreationDate]' \
  --output table \
  --region us-east-1

# Expected: State = available
```

---

## Phase 2: Infrastructure Deployment (20 minutes)

### Step 1: Configure Terraform Backend

```bash
cd ../environments/dev

# Create S3 bucket for Terraform state
BUCKET_NAME="jenkins-terraform-state-$(aws sts get-caller-identity --query Account --output text)"

aws s3 mb s3://$BUCKET_NAME --region us-east-1

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket $BUCKET_NAME \
  --versioning-configuration Status=Enabled \
  --region us-east-1

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name jenkins-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1

# Configure backend
cat > backend.tf <<EOF
terraform {
  backend "s3" {
    bucket         = "$BUCKET_NAME"
    key            = "jenkins/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "jenkins-terraform-locks"
    encrypt        = true
  }
}
EOF
```

### Step 2: Configure Terraform Variables

```bash
# Create terraform.tfvars
cat > terraform.tfvars <<EOF
# Environment Configuration
environment = "dev"
project_name = "jenkins-enterprise-platform"

# Network Configuration
vpc_cidr = "10.1.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
public_subnet_cidrs = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
private_subnet_cidrs = ["10.1.11.0/24", "10.1.12.0/24", "10.1.13.0/24"]

# Cost Optimization
single_nat_gateway = true  # Saves ~\$90/month

# Jenkins Configuration
jenkins_instance_type = "t3.small"
jenkins_desired_capacity = 1
jenkins_min_size = 1
jenkins_max_size = 3

# EFS Configuration
efs_performance_mode = "generalPurpose"
efs_throughput_mode = "bursting"

# Monitoring
enable_cloudwatch_dashboard = true
enable_detailed_monitoring = true

# Backup
backup_retention_days = 30

# Tags
tags = {
  Environment = "dev"
  Project     = "jenkins-enterprise-platform"
  ManagedBy   = "terraform"
  Owner       = "devops-team"
}
EOF
```

### Step 3: Initialize Terraform

```bash
# Initialize Terraform
terraform init

# Expected output:
# Terraform has been successfully initialized!

# Validate configuration
terraform validate

# Expected output:
# Success! The configuration is valid.
```

### Step 4: Plan Infrastructure

```bash
# Create execution plan
terraform plan -out=tfplan

# Review the plan
# Expected: ~50-60 resources to be created

# Save plan summary
terraform show -json tfplan | jq '.resource_changes | length'
```

### Step 5: Deploy Infrastructure

```bash
# Apply infrastructure (takes ~15-18 minutes)
terraform apply tfplan

# Or apply with auto-approve
terraform apply -auto-approve

# Expected output:
# Apply complete! Resources: 58 added, 0 changed, 0 destroyed.
#
# Outputs:
# alb_dns_name = "dev-jenkins-alb-121130223.us-east-1.elb.amazonaws.com"
# jenkins_url = "http://dev-jenkins-alb-121130223.us-east-1.elb.amazonaws.com:8080"
# ...
```

### Step 6: Save Outputs

```bash
# Save all outputs
terraform output > outputs.txt

# Get specific outputs
export JENKINS_URL=$(terraform output -raw jenkins_url)
export ALB_DNS=$(terraform output -raw alb_dns_name)
export EFS_ID=$(terraform output -raw efs_id)

echo "Jenkins URL: $JENKINS_URL"
echo "ALB DNS: $ALB_DNS"
echo "EFS ID: $EFS_ID"
```

---

## Phase 3: Verification & Access (10 minutes)

### Step 1: Wait for Instances to be Healthy

```bash
# Get target group ARN
TG_ARN=$(terraform output -raw target_group_arn)

# Monitor target health (wait 5-10 minutes)
watch -n 10 "aws elbv2 describe-target-health \
  --target-group-arn $TG_ARN \
  --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State,TargetHealth.Reason]' \
  --output table \
  --region us-east-1"

# Press Ctrl+C when status shows "healthy"
```

### Step 2: Get Jenkins Admin Password

```bash
# Method 1: From SSM Parameter Store (recommended)
ADMIN_PASSWORD=$(aws ssm get-parameter \
  --name '/jenkins/dev/admin-password' \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text \
  --region us-east-1)

echo "Admin Password: $ADMIN_PASSWORD"

# Method 2: From instance directly
INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names dev-jenkins-enterprise-platform-asg \
  --query 'AutoScalingGroups[0].Instances[0].InstanceId' \
  --output text \
  --region us-east-1)

COMMAND_ID=$(aws ssm send-command \
  --instance-ids $INSTANCE_ID \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["cat /var/lib/jenkins/secrets/initialAdminPassword"]' \
  --query 'Command.CommandId' \
  --output text \
  --region us-east-1)

# Wait 5 seconds
sleep 5

aws ssm get-command-invocation \
  --command-id $COMMAND_ID \
  --instance-id $INSTANCE_ID \
  --query 'StandardOutputContent' \
  --output text \
  --region us-east-1
```

### Step 3: Access Jenkins

```bash
# Open Jenkins in browser
echo "Jenkins URL: $JENKINS_URL"
echo "Username: admin"
echo "Password: $ADMIN_PASSWORD"

# macOS
open $JENKINS_URL

# Linux
xdg-open $JENKINS_URL

# Or manually navigate to the URL
```

### Step 4: Initial Jenkins Setup

```bash
# 1. Login with admin credentials
# 2. Install suggested plugins (or select custom plugins)
# 3. Create first admin user (optional, or continue as admin)
# 4. Configure Jenkins URL (should be pre-filled)
# 5. Start using Jenkins!
```

---

## Phase 4: Blue-Green Deployment Setup (5 minutes)

### Step 1: Verify Lambda Orchestrator

```bash
# Check Lambda function
aws lambda get-function \
  --function-name jenkins-enterprise-platform-dev-deployment-orchestrator \
  --query '[FunctionName,Runtime,State,LastUpdateStatus]' \
  --output table \
  --region us-east-1

# Expected: State = Active
```

### Step 2: Verify Blue-Green ASGs

```bash
# Check both ASGs
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names \
    jenkins-enterprise-platform-dev-blue-asg \
    jenkins-enterprise-platform-dev-green-asg \
  --query 'AutoScalingGroups[*].[AutoScalingGroupName,DesiredCapacity,MinSize,MaxSize]' \
  --output table \
  --region us-east-1

# Expected: Blue = 1 instance, Green = 0 instances
```

### Step 3: Test Blue-Green Deployment

```bash
# Trigger deployment
aws lambda invoke \
  --function-name jenkins-enterprise-platform-dev-deployment-orchestrator \
  --payload '{"action": "deploy"}' \
  --region us-east-1 \
  response.json

# Check response
cat response.json

# Monitor deployment (5-8 minutes)
watch -n 10 'aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names \
    jenkins-enterprise-platform-dev-blue-asg \
    jenkins-enterprise-platform-dev-green-asg \
  --query "AutoScalingGroups[*].[AutoScalingGroupName,DesiredCapacity]" \
  --output table \
  --region us-east-1'

# Verify zero downtime
while true; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" $JENKINS_URL)
  echo "$(date +%T) - HTTP Status: $STATUS"
  sleep 2
done
# Press Ctrl+C to stop
# Expected: All responses should be 200 or 403 (no 5xx errors)
```

---

## Phase 5: Monitoring Setup (5 minutes)

### Step 1: Access CloudWatch Dashboard

```bash
# Get dashboard name
DASHBOARD_NAME=$(aws cloudwatch list-dashboards \
  --query 'DashboardEntries[?contains(DashboardName, `dev-jenkins`)].DashboardName' \
  --output text \
  --region us-east-1)

echo "Dashboard: $DASHBOARD_NAME"

# Open dashboard URL
echo "https://console.aws.amazon.com/cloudwatch/home?region=us-east-1#dashboards:name=$DASHBOARD_NAME"
```

### Step 2: Verify Alarms

```bash
# List all alarms
aws cloudwatch describe-alarms \
  --alarm-name-prefix dev-jenkins \
  --query 'MetricAlarms[*].[AlarmName,StateValue,MetricName,Threshold]' \
  --output table \
  --region us-east-1

# Expected: 3-5 alarms in OK state
```

### Step 3: Check Log Groups

```bash
# List log groups
aws logs describe-log-groups \
  --log-group-name-prefix /jenkins/dev \
  --query 'logGroups[*].[logGroupName,retentionInDays]' \
  --output table \
  --region us-east-1

# View recent logs
aws logs tail /jenkins/dev/application --since 10m --region us-east-1
```

### Step 4: Configure SNS Notifications (Optional)

```bash
# Get SNS topic ARN
SNS_TOPIC=$(aws sns list-topics \
  --query 'Topics[?contains(TopicArn, `jenkins`)].TopicArn' \
  --output text \
  --region us-east-1)

# Subscribe email to alerts
aws sns subscribe \
  --topic-arn $SNS_TOPIC \
  --protocol email \
  --notification-endpoint your-email@example.com \
  --region us-east-1

# Confirm subscription via email
echo "Check your email and confirm the subscription"
```

---

## Phase 6: Backup Configuration (5 minutes)

### Step 1: Verify Backup Plan

```bash
# List backup plans
aws backup list-backup-plans \
  --query 'BackupPlansList[?contains(BackupPlanName, `jenkins`)]' \
  --output table \
  --region us-east-1

# Get backup plan details
BACKUP_PLAN_ID=$(aws backup list-backup-plans \
  --query 'BackupPlansList[?contains(BackupPlanName, `jenkins`)].BackupPlanId' \
  --output text \
  --region us-east-1)

aws backup get-backup-plan \
  --backup-plan-id $BACKUP_PLAN_ID \
  --region us-east-1
```

### Step 2: Trigger Manual Backup (Optional)

```bash
# Get EFS ARN
EFS_ARN=$(terraform output -raw efs_arn)

# Get backup role ARN
BACKUP_ROLE=$(aws iam list-roles \
  --query 'Roles[?contains(RoleName, `backup`)].Arn' \
  --output text)

# Start backup job
aws backup start-backup-job \
  --backup-vault-name Default \
  --resource-arn $EFS_ARN \
  --iam-role-arn $BACKUP_ROLE \
  --region us-east-1

# Monitor backup
aws backup list-backup-jobs \
  --by-resource-arn $EFS_ARN \
  --region us-east-1
```

### Step 3: Verify S3 Backup Bucket

```bash
# List backup bucket
aws s3 ls | grep jenkins-backup

# Check bucket versioning
BACKUP_BUCKET=$(terraform output -raw backup_bucket_name)
aws s3api get-bucket-versioning \
  --bucket $BACKUP_BUCKET \
  --region us-east-1
```

---

## Phase 7: Security Validation (5 minutes)

### Step 1: Verify Encryption

```bash
# Check EBS encryption
aws ec2 describe-volumes \
  --filters "Name=tag:Environment,Values=dev" \
  --query 'Volumes[*].[VolumeId,Encrypted,KmsKeyId]' \
  --output table \
  --region us-east-1

# Check EFS encryption
aws efs describe-file-systems \
  --query 'FileSystems[?Tags[?Key==`Environment` && Value==`dev`]].[FileSystemId,Encrypted,KmsKeyId]' \
  --output table \
  --region us-east-1

# Expected: All volumes encrypted = True
```

### Step 2: Verify VPC Flow Logs

```bash
# Check Flow Logs
aws ec2 describe-flow-logs \
  --filter "Name=tag:Environment,Values=dev" \
  --query 'FlowLogs[*].[FlowLogId,FlowLogStatus,ResourceId]' \
  --output table \
  --region us-east-1

# Expected: FlowLogStatus = ACTIVE
```

### Step 3: Review Security Groups

```bash
# Check for overly permissive rules
aws ec2 describe-security-groups \
  --filters "Name=tag:Environment,Values=dev" \
  --query 'SecurityGroups[*].[GroupName,IpPermissions[?contains(IpRanges[].CidrIp, `0.0.0.0/0`)]]' \
  --region us-east-1

# Expected: Only ALB should have 0.0.0.0/0 on port 8080
```

### Step 4: Run Security Scans

```bash
cd ../..

# TFSec scan
docker run --rm -v $(pwd):/src aquasec/tfsec /src

# Trivy scan
docker run --rm -v $(pwd):/src aquasec/trivy fs --severity HIGH,CRITICAL /src

# Checkov scan
docker run --rm -v $(pwd):/tf bridgecrew/checkov -d /tf --quiet
```

---

## Phase 8: Testing & Validation (10 minutes)

### Step 1: Run Automated Tests

```bash
# Run full test suite
./scripts/test-platform.sh

# Expected output:
# ✓ Passed: 40+
# ✗ Failed: 0
# ⚠ Warnings: 0-5
```

### Step 2: Manual Verification

```bash
# 1. Jenkins accessible
curl -I $JENKINS_URL

# 2. Create test job in Jenkins UI
# - Login to Jenkins
# - New Item → Pipeline
# - Name: test-pipeline
# - Pipeline script:
pipeline {
    agent any
    stages {
        stage('Test') {
            steps {
                echo 'Hello from Jenkins!'
            }
        }
    }
}
# - Save and Build Now

# 3. Verify EFS mount
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

### Step 3: Load Testing

```bash
# Install Apache Bench
brew install apache-bench  # macOS
# sudo apt-get install apache2-utils  # Linux

# Run load test
ab -n 1000 -c 50 $JENKINS_URL/

# Expected:
# - Requests per second: >50
# - Time per request: <1000ms
# - Failed requests: 0
```

---

## Post-Deployment Configuration

### Configure Jenkins Plugins

```bash
# Login to Jenkins and install recommended plugins:
# - Pipeline
# - Git
# - GitHub
# - Docker Pipeline
# - AWS Steps
# - Terraform
# - Blue Ocean
# - OWASP Dependency Check
# - SonarQube Scanner

# Or install via CLI
JENKINS_CLI="java -jar jenkins-cli.jar -s $JENKINS_URL -auth admin:$ADMIN_PASSWORD"

# Download CLI
wget $JENKINS_URL/jnlpJars/jenkins-cli.jar

# Install plugins
$JENKINS_CLI install-plugin pipeline-model-definition
$JENKINS_CLI install-plugin git
$JENKINS_CLI install-plugin github
$JENKINS_CLI install-plugin docker-workflow
$JENKINS_CLI install-plugin aws-java-sdk
$JENKINS_CLI install-plugin terraform

# Restart Jenkins
$JENKINS_CLI safe-restart
```

### Configure AWS Credentials in Jenkins

```bash
# 1. Go to Jenkins → Manage Jenkins → Manage Credentials
# 2. Click (global) → Add Credentials
# 3. Kind: AWS Credentials
# 4. ID: aws-credentials
# 5. Access Key ID: [YOUR_KEY]
# 6. Secret Access Key: [YOUR_SECRET]
# 7. Save
```

### Create Sample Pipeline

```bash
# Create Jenkinsfile in your repository
cat > Jenkinsfile <<'EOF'
pipeline {
    agent any
    
    environment {
        AWS_REGION = 'us-east-1'
        AWS_CREDENTIALS = 'aws-credentials'
    }
    
    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }
        
        stage('Build') {
            steps {
                echo 'Building application...'
                sh 'echo "Build successful"'
            }
        }
        
        stage('Test') {
            steps {
                echo 'Running tests...'
                sh 'echo "Tests passed"'
            }
        }
        
        stage('Deploy') {
            steps {
                echo 'Deploying to AWS...'
                withAWS(credentials: env.AWS_CREDENTIALS, region: env.AWS_REGION) {
                    sh 'aws s3 ls'
                }
            }
        }
    }
    
    post {
        success {
            echo 'Pipeline completed successfully!'
        }
        failure {
            echo 'Pipeline failed!'
        }
    }
}
EOF
```

---

## Disaster Recovery Setup (Optional)

### Deploy to DR Region

```bash
# Create DR environment
cd environments/production-dr

# Configure for DR region
cat > terraform.tfvars <<EOF
environment = "production-dr"
aws_region = "us-west-2"
vpc_cidr = "10.4.0.0/16"
# ... copy other settings from production
EOF

# Initialize and deploy
terraform init
terraform plan
terraform apply -auto-approve

# Replicate AMI to DR region
SOURCE_AMI=$GOLDEN_AMI_ID
aws ec2 copy-image \
  --source-region us-east-1 \
  --source-image-id $SOURCE_AMI \
  --name "jenkins-golden-ami-dr-$(date +%Y%m%d)" \
  --region us-west-2
```

---

## Cost Monitoring Setup

### Enable Cost Allocation Tags

```bash
# Activate cost allocation tags
aws ce update-cost-allocation-tags-status \
  --cost-allocation-tags-status \
    TagKey=Environment,Status=Active \
    TagKey=Project,Status=Active \
    TagKey=Owner,Status=Active \
  --region us-east-1

# Create cost budget
aws budgets create-budget \
  --account-id $(aws sts get-caller-identity --query Account --output text) \
  --budget file://budget.json \
  --notifications-with-subscribers file://notifications.json

# budget.json
cat > budget.json <<EOF
{
  "BudgetName": "jenkins-monthly-budget",
  "BudgetLimit": {
    "Amount": "150",
    "Unit": "USD"
  },
  "TimeUnit": "MONTHLY",
  "BudgetType": "COST"
}
EOF

# notifications.json
cat > notifications.json <<EOF
[
  {
    "Notification": {
      "NotificationType": "ACTUAL",
      "ComparisonOperator": "GREATER_THAN",
      "Threshold": 80
    },
    "Subscribers": [
      {
        "SubscriptionType": "EMAIL",
        "Address": "your-email@example.com"
      }
    ]
  }
]
EOF
```

---

## Troubleshooting Common Issues

### Issue 1: Terraform Apply Fails

```bash
# Check AWS credentials
aws sts get-caller-identity

# Check Terraform state
terraform state list

# Refresh state
terraform refresh

# Re-run apply
terraform apply -auto-approve
```

### Issue 2: Jenkins Not Accessible

```bash
# Check target health
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw target_group_arn) \
  --region us-east-1

# Check instance status
aws ec2 describe-instance-status \
  --instance-ids $INSTANCE_ID \
  --region us-east-1

# Check user data logs
aws ssm send-command \
  --instance-ids $INSTANCE_ID \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["tail -100 /var/log/cloud-init-output.log"]' \
  --region us-east-1
```

### Issue 3: EFS Not Mounting

```bash
# Check EFS status
aws efs describe-file-systems \
  --file-system-id $EFS_ID \
  --region us-east-1

# Check mount targets
aws efs describe-mount-targets \
  --file-system-id $EFS_ID \
  --region us-east-1

# Check security groups
aws ec2 describe-security-groups \
  --filters "Name=tag:Name,Values=*efs*" \
  --region us-east-1

# Manual mount test
aws ssm send-command \
  --instance-ids $INSTANCE_ID \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["sudo mount -t nfs4 -o nfsvers=4.1 $EFS_ID.efs.us-east-1.amazonaws.com:/ /mnt/test"]' \
  --region us-east-1
```

---

## Cleanup (If Needed)

### Destroy Infrastructure

```bash
# Destroy all resources
cd environments/dev
terraform destroy -auto-approve

# Delete S3 buckets (must be empty first)
aws s3 rm s3://$(terraform output -raw backup_bucket_name) --recursive
aws s3 rb s3://$(terraform output -raw backup_bucket_name)

# Delete Terraform state bucket
aws s3 rm s3://$BUCKET_NAME --recursive
aws s3 rb s3://$BUCKET_NAME

# Delete DynamoDB table
aws dynamodb delete-table \
  --table-name jenkins-terraform-locks \
  --region us-east-1

# Deregister AMIs
aws ec2 deregister-image \
  --image-id $GOLDEN_AMI_ID \
  --region us-east-1
```

---

## Quick Reference Commands

```bash
# Get Jenkins URL
terraform output -raw jenkins_url

# Get admin password
aws ssm get-parameter \
  --name '/jenkins/dev/admin-password' \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text \
  --region us-east-1

# Check target health
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw target_group_arn) \
  --region us-east-1

# Trigger blue-green deployment
aws lambda invoke \
  --function-name jenkins-enterprise-platform-dev-deployment-orchestrator \
  --region us-east-1 \
  response.json

# View logs
aws logs tail /jenkins/dev/application --follow --region us-east-1

# Run tests
./scripts/test-platform.sh
```

---

## Success Checklist

- [ ] Prerequisites installed (Terraform, AWS CLI, Packer)
- [ ] AWS credentials configured
- [ ] Golden AMI created successfully
- [ ] Terraform backend configured
- [ ] Infrastructure deployed (58 resources)
- [ ] Jenkins accessible via ALB
- [ ] Admin password retrieved
- [ ] Blue-green ASGs configured
- [ ] Lambda orchestrator functional
- [ ] CloudWatch dashboard created
- [ ] Alarms configured
- [ ] Backup plan active
- [ ] Security validation passed
- [ ] All tests passed
- [ ] Sample pipeline created

---

## Next Steps

1. **Configure Jenkins**
   - Install additional plugins
   - Set up user accounts and permissions
   - Configure build agents

2. **Create Pipelines**
   - Import existing pipelines
   - Create new pipeline jobs
   - Configure webhooks

3. **Set Up Integrations**
   - GitHub/GitLab integration
   - Slack notifications
   - SonarQube integration

4. **Production Deployment**
   - Deploy to staging environment
   - Test thoroughly
   - Deploy to production with blue-green

5. **Ongoing Maintenance**
   - Monitor CloudWatch dashboards
   - Review security scans
   - Update AMIs quarterly
   - Test disaster recovery

---

**Implementation Time**: 45-60 minutes  
**Monthly Cost**: ~$110  
**Support**: See docs/TROUBLESHOOTING.md  
**Testing**: See docs/TESTING_GUIDE.md

**Last Updated**: October 24, 2025  
**Version**: 1.0
