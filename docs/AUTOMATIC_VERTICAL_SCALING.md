# Automatic Vertical Scaling for Jenkins Master

## Overview

Your Jenkins master automatically scales instance type based on CPU and memory usage.

## How It Works

```
Low Load:              High Load:
┌─────────┐           ┌─────────┐
│t3.small │    →      │t3.large │
│2GB RAM  │           │8GB RAM  │
└─────────┘           └─────────┘
  $15/month             $60/month
```

## Scaling Logic

### Scale UP When:
- CPU > 75% for 15 minutes
- OR Memory > 80% for 10 minutes

### Scale DOWN When:
- CPU < 30% AND Memory < 40% for 30 minutes

### Instance Types (Auto-Selected):
1. **t3.small** - 2 vCPU, 2GB RAM - $15/month (default)
2. **t3.medium** - 2 vCPU, 4GB RAM - $30/month (auto-scales)
3. **t3.large** - 2 vCPU, 8GB RAM - $60/month (auto-scales)

## Deployment

```bash
# 1. Apply Terraform (adds vertical scaling)
cd /Users/abdihakimsaid/sandbox/jenkins-enterprise-platform
terraform apply

# 2. Verify Lambda function created
aws lambda list-functions \
  --query 'Functions[?contains(FunctionName, `vertical-scaler`)]' \
  --region us-east-1

# 3. Check EventBridge rule
aws events list-rules \
  --name-prefix jenkins-enterprise-platform-dev-vertical \
  --region us-east-1
```

## Monitoring

### Check Current Instance Type:
```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names jenkins-enterprise-platform-dev-blue-asg \
  --query 'AutoScalingGroups[0].LaunchTemplate' \
  --region us-east-1
```

### View Scaling Events:
```bash
aws logs tail /aws/lambda/jenkins-enterprise-platform-dev-vertical-scaler \
  --follow \
  --region us-east-1
```

### Manual Trigger:
```bash
aws lambda invoke \
  --function-name jenkins-enterprise-platform-dev-vertical-scaler \
  --region us-east-1 \
  response.json && cat response.json
```

## How Scaling Happens

1. **Lambda checks metrics every 10 minutes**
2. **If thresholds exceeded:**
   - Creates new launch template version with larger instance type
   - Updates ASG to use new template
   - Triggers instance refresh (rolling update)
3. **Blue-green deployment handles the switch**
   - Old instance (t3.small) drains connections
   - New instance (t3.large) launches
   - Zero downtime!
4. **SNS notification sent**

## Cost Impact

```
Normal Load (t3.small):     $15/month
Medium Load (t3.medium):    $30/month
High Load (t3.large):       $60/month

Average (mostly small):     ~$20/month
```

## Benefits

✅ **Automatic**: No manual intervention
✅ **Cost-Effective**: Only pay for what you need
✅ **Zero-Downtime**: Uses blue-green deployment
✅ **Smart**: Scales based on actual usage
✅ **Safe**: Gradual rollout with health checks

## Disable Automatic Scaling

```bash
# Disable EventBridge rule
aws events disable-rule \
  --name jenkins-enterprise-platform-dev-vertical-scaling-check \
  --region us-east-1
```

## Manual Scaling (Override)

```bash
# Force specific instance type
# Edit: modules/blue-green-deployment/main.tf
instance_type = "t3.large"  # Fixed size

# Apply
terraform apply
```

---

**Status**: Ready to deploy
**Cost**: ~$0.20/month for Lambda + actual instance costs
**Monitoring**: CloudWatch + SNS notifications
