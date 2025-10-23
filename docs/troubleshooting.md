# Jenkins Enterprise Platform - Troubleshooting Guide

## Golden AMI Generation & EFS Mounting Issues

### Problem Summary
Multiple instances running different AMIs with EFS mounting failures causing Jenkins startup issues.

---

## Issue 1: Inconsistent AMI Usage Across Instances

### **Symptoms**
- 3 different AMIs running simultaneously
- Instances using wrong/outdated AMIs
- Manual intervention required for AMI updates

### **Root Cause**
Broken conditional logic in Terraform AMI selection:
```hcl
# BROKEN CODE
image_id = var.jenkins_ami_id != "" ? var.jenkins_ami_id : data.aws_ami.jenkins_golden.id
```

**Problem**: `var.jenkins_ami_id` defaults to `null` (not empty string), causing logic to use `null` instead of latest golden AMI.

### **Solution**
```hcl
# FIXED CODE
image_id = data.aws_ami.jenkins_golden.id
```

**Files Modified:**
- `modules/jenkins/main.tf` (line 36)

---

## Issue 2: EFS Mounting Failures

### **Symptoms**
```bash
E: Unable to locate package amazon-efs-utils
❌ EFS mount failed, using local storage
```

### **Root Causes**

#### A. Security Hardening Removing Required Services
```bash
# BROKEN: Removes rpcbind needed for EFS
sudo apt purge -y nis rpcbind
```

**Fix:**
```bash
# FIXED: Keep rpcbind for EFS support
sudo apt purge -y nis
# Note: Keeping nfs-common and rpcbind for EFS support
```

**Files Modified:**
- `packer/scripts/security-hardening.sh` (line 15)

#### B. Duplicate EFS Mount Logic in User Data
**Problem**: User data script had conflicting mount logic causing failures.

**Solution**: Complete rewrite of `modules/jenkins/user_data.sh` with:
- Removed duplicate mount code (lines 73-137)
- Added fallback EFS utils installation
- Multiple mount methods (NFS4 + EFS utils)
- Better error handling and diagnostics
- Proper backup/restore logic

---

## Issue 3: Packer Validation Failures

### **Symptoms**
```bash
mount.efs --version || (echo 'EFS utils validation failed' && exit 1)
```

### **Root Cause**
Packer trying to validate EFS utils before they're installed.

### **Solution**
```bash
# FIXED: Use available command for validation
mount.nfs4 --version || (echo 'EFS utils validation failed' && exit 1)
```

---

## Complete Fix Implementation

### **Step 1: Fix AMI Selection Logic**
```bash
# File: modules/jenkins/main.tf
- image_id = var.jenkins_ami_id != "" ? var.jenkins_ami_id : data.aws_ami.jenkins_golden.id
+ image_id = data.aws_ami.jenkins_golden.id
```

### **Step 2: Fix Security Hardening**
```bash
# File: packer/scripts/security-hardening.sh
- sudo apt purge -y nis rpcbind
+ sudo apt purge -y nis
+ # Note: Keeping nfs-common and rpcbind for EFS support
```

### **Step 3: Fix User Data Script**
Complete rewrite of `modules/jenkins/user_data.sh` with:
- Enhanced error handling
- Multiple EFS mount methods
- Fallback mechanisms
- Better diagnostics

### **Step 4: Rebuild and Deploy**
```bash
# 1. Rebuild Golden AMI
cd packer
packer build jenkins-ami.pkr.hcl

# 2. Apply Terraform changes
terraform apply

# 3. Refresh running instances
aws autoscaling start-instance-refresh \
    --region us-east-1 \
    --auto-scaling-group-name "dev-jenkins-enterprise-platform-asg"
```

---

## Verification Steps

### **1. Check AMI Consistency**
```bash
aws ec2 describe-instances \
    --region us-east-1 \
    --filters "Name=tag:Name,Values=*jenkins*" "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].[InstanceId,ImageId,Tags[?Key==`Name`].Value|[0]]'
```

### **2. Verify EFS Mounting**
```bash
# SSH to instance and check:
sudo mount | grep efs
sudo systemctl status jenkins
curl -I http://localhost:8080
```

### **3. Check Jenkins Access**
```bash
# Get ALB URL
aws elbv2 describe-load-balancers \
    --region us-east-1 \
    --names "dev-jenkins-alb" \
    --query 'LoadBalancers[0].DNSName'

# Get admin password
aws ssm get-parameter \
    --region us-east-1 \
    --name "/jenkins/dev/admin-password" \
    --with-decryption \
    --query 'Parameter.Value'
```

---

## Prevention Measures

### **1. Automated AMI Updates**
Implement EventBridge rule to trigger infrastructure updates when new golden AMI is created.

### **2. Health Checks**
Enhanced monitoring for:
- EFS mount status
- Jenkins service health
- AMI consistency across instances

### **3. Testing Pipeline**
- Validate Packer builds before deployment
- Test EFS mounting in staging
- Verify Jenkins functionality post-deployment

---

## Common Error Messages & Solutions

| Error | Cause | Solution |
|-------|-------|----------|
| `E: Unable to locate package amazon-efs-utils` | Missing EFS utils in runtime | Fixed in user data script |
| `❌ EFS mount failed` | rpcbind removed by security hardening | Keep rpcbind service |
| `Different AMIs running` | Broken conditional logic | Use data source directly |
| `Jenkins not responding` | EFS mount blocking startup | Enhanced error handling |

---

## Architecture Impact

### **Before Fix**
- 3 different AMIs running
- Manual AMI management
- EFS mounting failures
- Jenkins startup issues

### **After Fix**
- ✅ Consistent AMI usage
- ✅ Automatic latest AMI selection
- ✅ Reliable EFS mounting
- ✅ Robust error handling
- ✅ Better diagnostics

---

## Lessons Learned

1. **Always test conditional logic** with actual variable states
2. **Security hardening must consider application requirements**
3. **User data scripts need comprehensive error handling**
4. **Validation steps should match runtime environment**
5. **Infrastructure automation requires consistent AMI management**

---

**Date**: October 23, 2025  
**Author**: Abdihakim Said  
**Project**: Jenkins Enterprise Platform  
**Epic**: Epic-2-Golden-Image
