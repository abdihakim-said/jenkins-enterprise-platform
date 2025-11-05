# Quick Start - Deploy in 30 Minutes

## Prerequisites (5 minutes)

```bash
# Install tools
brew install terraform awscli packer  # macOS
# OR
sudo apt-get install terraform awscli packer  # Linux

# Configure AWS
aws configure
# Enter: Access Key, Secret Key, Region (us-east-1), Format (json)

# Clone repo
git clone https://github.com/yourusername/jenkins-enterprise-platform.git
cd jenkins-enterprise-platform
```

---

## 1. Build Golden AMI (10 minutes)

```bash
cd packer

# Build AMI
packer init jenkins-ami.pkr.hcl
packer build jenkins-ami.pkr.hcl

# Save AMI ID
export AMI_ID=$(cat manifest.json | jq -r '.builds[0].artifact_id' | cut -d':' -f2)
echo "AMI: $AMI_ID"
```

---

## 2. Deploy Infrastructure (15 minutes)

```bash
cd ../environments/dev

# Create backend bucket
export BUCKET="jenkins-tf-state-$(aws sts get-caller-identity --query Account --output text)"
aws s3 mb s3://$BUCKET --region us-east-1
aws s3api put-bucket-versioning --bucket $BUCKET --versioning-configuration Status=Enabled

# Create lock table
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
    bucket         = "$BUCKET"
    key            = "jenkins/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "jenkins-terraform-locks"
    encrypt        = true
  }
}
EOF

# Deploy
terraform init
terraform apply -auto-approve

# Save outputs
export JENKINS_URL=$(terraform output -raw jenkins_url)
export TG_ARN=$(terraform output -raw target_group_arn)
```

---

## 3. Wait for Healthy Targets (5 minutes)

```bash
# Monitor until "healthy"
watch -n 10 "aws elbv2 describe-target-health \
  --target-group-arn $TG_ARN \
  --query 'TargetHealthDescriptions[*].[TargetHealth.State]' \
  --output text \
  --region us-east-1"
```

---

## 4. Access Jenkins

```bash
# Get password
export PASSWORD=$(aws ssm get-parameter \
  --name '/jenkins/dev/admin-password' \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text \
  --region us-east-1)

# Display credentials
echo "URL: $JENKINS_URL"
echo "Username: admin"
echo "Password: $PASSWORD"

# Open browser
open $JENKINS_URL  # macOS
# xdg-open $JENKINS_URL  # Linux
```

---

## 5. Test Blue-Green Deployment

```bash
# Trigger deployment
aws lambda invoke \
  --function-name jenkins-enterprise-platform-dev-deployment-orchestrator \
  --region us-east-1 \
  response.json

# Monitor (5-8 minutes)
watch -n 10 'aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names \
    jenkins-enterprise-platform-dev-blue-asg \
    jenkins-enterprise-platform-dev-green-asg \
  --query "AutoScalingGroups[*].[AutoScalingGroupName,DesiredCapacity]" \
  --output table \
  --region us-east-1'

# Verify zero downtime
while true; do
  curl -s -o /dev/null -w "$(date +%T) - HTTP: %{http_code}\n" $JENKINS_URL
  sleep 2
done
```

---

## 6. Run Tests

```bash
cd ../..
./scripts/test-platform.sh

# Expected: ✓ 40+ tests passed
```

---

## Quick Commands

```bash
# Get Jenkins URL
terraform output -raw jenkins_url

# Get password
aws ssm get-parameter --name '/jenkins/dev/admin-password' --with-decryption --query 'Parameter.Value' --output text --region us-east-1

# Check health
aws elbv2 describe-target-health --target-group-arn $(terraform output -raw target_group_arn) --region us-east-1

# View logs
aws logs tail /jenkins/dev/application --follow --region us-east-1

# Trigger blue-green
aws lambda invoke --function-name jenkins-enterprise-platform-dev-deployment-orchestrator --region us-east-1 response.json

# Destroy (cleanup)
terraform destroy -auto-approve
```

---

## Troubleshooting

**Jenkins not accessible?**
```bash
# Check target health
aws elbv2 describe-target-health --target-group-arn $TG_ARN --region us-east-1

# Check instance logs
INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names dev-jenkins-enterprise-platform-asg --query 'AutoScalingGroups[0].Instances[0].InstanceId' --output text --region us-east-1)
aws ssm send-command --instance-ids $INSTANCE_ID --document-name "AWS-RunShellScript" --parameters 'commands=["tail -100 /var/log/cloud-init-output.log"]' --region us-east-1
```

**EFS not mounting?**
```bash
# Check EFS
aws efs describe-file-systems --region us-east-1

# Check mount targets
aws efs describe-mount-targets --file-system-id $(terraform output -raw efs_id) --region us-east-1
```

---

## What You Get

✅ Jenkins accessible at ALB URL  
✅ Zero-downtime blue-green deployments  
✅ Auto Scaling (1-3 instances)  
✅ EFS persistent storage  
✅ CloudWatch monitoring & alarms  
✅ Automated backups (30-day retention)  
✅ Lambda orchestration  
✅ Multi-AZ high availability  
✅ Encrypted volumes (EBS, EFS)  
✅ VPC Flow Logs  

**Cost**: ~$110/month  
**Deployment Time**: 30 minutes  
**Availability**: 99.99%

---

**Full Documentation**: See `docs/IMPLEMENTATION_GUIDE.md`  
**Testing**: See `docs/TESTING_GUIDE.md`  
**Troubleshooting**: See `docs/TROUBLESHOOTING.md`
