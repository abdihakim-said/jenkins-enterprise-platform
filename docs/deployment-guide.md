# 🚀 Jenkins Enterprise Platform - Deployment Guide

## 📋 Table of Contents

- [Prerequisites](#prerequisites)
- [Environment Setup](#environment-setup)
- [Infrastructure Deployment](#infrastructure-deployment)
- [Application Configuration](#application-configuration)
- [Monitoring Setup](#monitoring-setup)
- [Security Configuration](#security-configuration)
- [Testing & Validation](#testing--validation)
- [Production Deployment](#production-deployment)

## Prerequisites

### 🔧 Required Tools

```bash
# macOS
brew install terraform packer ansible awscli jq

# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y terraform packer ansible awscli jq

# Verify installations
terraform --version
packer --version
ansible --version
aws --version
```

### ☁️ AWS Account Setup

1. **Create AWS Account** (if not already done)
2. **Configure AWS CLI**:
   ```bash
   aws configure
   # AWS Access Key ID: YOUR_ACCESS_KEY
   # AWS Secret Access Key: YOUR_SECRET_KEY
   # Default region name: us-east-1
   # Default output format: json
   ```

3. **Create EC2 Key Pair**:
   ```bash
   aws ec2 create-key-pair --key-name jenkins-key --query 'KeyMaterial' --output text > jenkins-key.pem
   chmod 400 jenkins-key.pem
   ```

## Environment Setup

### 🔧 Project Configuration

1. **Clone Repository**:
   ```bash
   git clone https://github.com/your-username/jenkins-enterprise-platform.git
   cd jenkins-enterprise-platform
   ```

2. **Set Environment Variables**:
   ```bash
   export AWS_REGION=us-east-1
   export ENVIRONMENT=staging
   export PROJECT_NAME=jenkins-enterprise-platform
   ```

3. **Configure Terraform Backend** (Optional):
   ```bash
   # Create S3 bucket for Terraform state
   aws s3 mb s3://your-terraform-state-bucket
   
   # Update backend configuration in terraform/environments/staging/main.tf
   ```

## Infrastructure Deployment

### 🏗️ Step-by-Step Deployment

#### **Phase 1: Core Infrastructure**

```bash
cd terraform/environments/staging

# Initialize Terraform
terraform init

# Review planned changes
terraform plan -var="environment=staging"

# Deploy core infrastructure
terraform apply -target=module.networking -auto-approve
terraform apply -target=module.security -auto-approve
terraform apply -target=module.efs -auto-approve
terraform apply -target=module.s3_backup -auto-approve
```

#### **Phase 2: Load Balancer & Auto Scaling**

```bash
# Deploy load balancer
terraform apply -target=module.load_balancer -auto-approve

# Deploy auto scaling groups
terraform apply -target=module.auto_scaling_blue -auto-approve

# Deploy monitoring
terraform apply -target=module.monitoring -auto-approve
```

#### **Phase 3: Complete Deployment**

```bash
# Deploy everything
terraform apply -auto-approve

# Get outputs
terraform output
```

### 📊 Deployment Validation

```bash
# Check infrastructure status
./scripts/validate-deployment.sh --environment staging

# Verify Jenkins accessibility
JENKINS_URL=$(terraform output -raw jenkins_url)
curl -I $JENKINS_URL/login

# Check EFS mount
EFS_ID=$(terraform output -raw efs_id)
aws efs describe-file-systems --file-system-id $EFS_ID
```

## Application Configuration

### 🔧 Jenkins Initial Setup

1. **Get Initial Admin Password**:
   ```bash
   aws ssm get-parameter --name "/jenkins/staging/admin-password" --with-decryption --query 'Parameter.Value' --output text
   ```

2. **Access Jenkins**:
   ```bash
   JENKINS_URL=$(terraform output -raw jenkins_url)
   echo "Jenkins URL: $JENKINS_URL"
   open $JENKINS_URL  # macOS
   # or visit the URL in your browser
   ```

3. **Complete Setup Wizard**:
   - Enter the admin password
   - Install suggested plugins
   - Create admin user
   - Configure Jenkins URL

### 🔌 Plugin Installation

Essential plugins for enterprise use:

```groovy
// Install via Jenkins CLI or Manage Plugins
def plugins = [
    'build-timeout',
    'credentials-binding',
    'timestamper',
    'ws-cleanup',
    'github-branch-source',
    'pipeline-github-lib',
    'pipeline-stage-view',
    'git',
    'ssh-slaves',
    'matrix-auth',
    'email-ext',
    'prometheus',
    'cloudwatch-logs',
    'aws-credentials',
    'docker-workflow',
    'kubernetes',
    'terraform',
    'ansible',
    'sonar',
    'dependency-check-jenkins-plugin'
]

plugins.each { plugin ->
    if (!Jenkins.instance.pluginManager.getPlugin(plugin)) {
        println "Installing plugin: ${plugin}"
        Jenkins.instance.updateCenter.getPlugin(plugin).deploy()
    }
}
```

## Monitoring Setup

### 📊 CloudWatch Configuration

CloudWatch dashboards and alarms are automatically configured. Verify setup:

```bash
# List CloudWatch alarms
aws cloudwatch describe-alarms --alarm-names "staging-jenkins-high-cpu" "staging-jenkins-high-memory"

# Check SNS topic
aws sns list-topics --query 'Topics[?contains(TopicArn, `jenkins-alerts`)]'
```

### 📈 Prometheus & Grafana Setup

1. **Access Grafana**:
   ```bash
   # Grafana runs on port 3000
   GRAFANA_URL="http://$(terraform output -raw jenkins_url | sed 's/:8080/:3000/')"
   echo "Grafana URL: $GRAFANA_URL"
   ```

2. **Import Dashboards**:
   - Jenkins Performance Dashboard
   - System Metrics Dashboard
   - AWS Infrastructure Dashboard

### 🚨 Alert Configuration

Configure Slack notifications:

```bash
# Set Slack webhook URL in SSM Parameter Store
aws ssm put-parameter \
    --name "/jenkins/staging/slack-webhook" \
    --value "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK" \
    --type "SecureString"
```

## Security Configuration

### 🔒 Security Hardening

Security hardening is automatically applied via user data scripts. Verify:

```bash
# Check security services status
INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=*jenkins*" --query 'Reservations[0].Instances[0].InstanceId' --output text)

# SSH to instance and check security services
ssh -i jenkins-key.pem ubuntu@$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text) << 'EOF'
sudo systemctl status fail2ban
sudo systemctl status ufw
sudo fail2ban-client status
sudo ufw status
EOF
```

### 🔐 SSL/TLS Configuration

For production, configure SSL certificate:

```bash
# Request ACM certificate
aws acm request-certificate \
    --domain-name jenkins.yourdomain.com \
    --validation-method DNS \
    --region us-east-1

# Update load balancer to use HTTPS
terraform apply -var="ssl_certificate_arn=arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
```

### 👤 User Management

Configure Jenkins security:

1. **Matrix-based Security**:
   - Navigate to Manage Jenkins → Configure Global Security
   - Enable "Matrix-based security"
   - Configure user permissions

2. **LDAP Integration** (Optional):
   ```groovy
   // Configure LDAP in Jenkins
   import jenkins.model.*
   import hudson.security.*
   
   def instance = Jenkins.getInstance()
   def ldapRealm = new LDAPSecurityRealm(
       "ldap://your-ldap-server:389",
       "dc=company,dc=com",
       "uid={0},ou=people,dc=company,dc=com",
       "cn=admin,dc=company,dc=com",
       "admin-password",
       false,
       false,
       null,
       null,
       null,
       null
   )
   instance.setSecurityRealm(ldapRealm)
   instance.save()
   ```

## Testing & Validation

### 🧪 Automated Testing

Run comprehensive tests:

```bash
# Infrastructure tests
cd tests/
python -m pytest test_infrastructure.py -v

# Security tests
python -m pytest test_security.py -v

# Performance tests
python -m pytest test_performance.py -v
```

### 🔍 Manual Validation Checklist

- [ ] Jenkins accessible via load balancer
- [ ] EFS mounted and writable
- [ ] S3 backup bucket accessible
- [ ] CloudWatch metrics flowing
- [ ] Security groups properly configured
- [ ] Auto scaling working
- [ ] Health checks passing
- [ ] SSL certificate valid (production)
- [ ] Monitoring alerts functional
- [ ] Backup and restore tested

### 📊 Performance Testing

```bash
# Load testing with Apache Bench
ab -n 1000 -c 10 http://your-jenkins-url/login

# Monitor during load test
watch -n 1 'aws cloudwatch get-metric-statistics --namespace AWS/ApplicationELB --metric-name RequestCount --dimensions Name=LoadBalancer,Value=staging-jenkins-alb --start-time $(date -u -d "5 minutes ago" +%Y-%m-%dT%H:%M:%S) --end-time $(date -u +%Y-%m-%dT%H:%M:%S) --period 60 --statistics Sum'
```

## Production Deployment

### 🏭 Production Considerations

1. **Multi-AZ RDS** (if using database):
   ```hcl
   # In terraform/environments/production/terraform.tfvars
   enable_rds = true
   rds_multi_az = true
   rds_backup_retention_period = 30
   ```

2. **Cross-Region Backup**:
   ```hcl
   enable_cross_region_replication = true
   replica_region = "us-west-2"
   ```

3. **Enhanced Monitoring**:
   ```hcl
   enable_detailed_monitoring = true
   enable_container_insights = true
   ```

### 🚀 Blue-Green Deployment

For zero-downtime deployments:

```bash
# Deploy to green environment
./scripts/blue-green-deploy.sh --environment production --target green

# Run smoke tests
./scripts/smoke-tests.sh --environment production --target green

# Switch traffic
./scripts/blue-green-deploy.sh --environment production --switch-traffic

# Monitor for 30 minutes
./scripts/monitor-deployment.sh --environment production --duration 30

# Cleanup old environment
./scripts/blue-green-deploy.sh --environment production --cleanup blue
```

### 📋 Production Deployment Checklist

- [ ] **Pre-deployment**:
  - [ ] Backup current configuration
  - [ ] Notify stakeholders
  - [ ] Prepare rollback plan
  - [ ] Verify monitoring systems

- [ ] **Deployment**:
  - [ ] Deploy to green environment
  - [ ] Run automated tests
  - [ ] Perform manual validation
  - [ ] Switch traffic gradually

- [ ] **Post-deployment**:
  - [ ] Monitor system health
  - [ ] Verify all services functional
  - [ ] Update documentation
  - [ ] Cleanup old resources

### 🔄 Rollback Procedure

If issues occur:

```bash
# Immediate rollback
./scripts/blue-green-deploy.sh --environment production --rollback

# Or manual rollback
aws elbv2 modify-target-group-attributes \
    --target-group-arn $(terraform output -raw blue_target_group_arn) \
    --attributes Key=deregistration_delay.timeout_seconds,Value=30

aws elbv2 modify-listener \
    --listener-arn $(terraform output -raw listener_arn) \
    --default-actions Type=forward,TargetGroupArn=$(terraform output -raw blue_target_group_arn)
```

## Maintenance & Operations

### 🔧 Regular Maintenance Tasks

1. **Weekly**:
   - Review CloudWatch metrics
   - Check security logs
   - Validate backups
   - Update plugins

2. **Monthly**:
   - Security patching
   - Capacity planning review
   - Disaster recovery testing
   - Cost optimization review

3. **Quarterly**:
   - Security audit
   - Performance tuning
   - Documentation updates
   - Training updates

### 📊 Monitoring & Alerting

Key metrics to monitor:

| Metric | Threshold | Action |
|--------|-----------|--------|
| CPU Utilization | > 80% | Scale out |
| Memory Usage | > 85% | Alert + Scale |
| Disk Usage | > 90% | Critical alert |
| Build Queue | > 20 jobs | Scale out |
| Failed Builds | > 10% | Investigate |
| Response Time | > 5 seconds | Performance review |

### 🚨 Incident Response

1. **Detection**: Automated alerts via CloudWatch/SNS
2. **Assessment**: Check dashboards and logs
3. **Response**: Auto-scaling or manual intervention
4. **Communication**: Update stakeholders
5. **Resolution**: Fix root cause
6. **Post-mortem**: Document lessons learned

---

## 📞 Support

For deployment issues:

1. **Check logs**: CloudWatch logs and system logs
2. **Review documentation**: This guide and troubleshooting docs
3. **Community support**: GitHub Issues
4. **Enterprise support**: AWS Support (if applicable)

## 🔄 Updates

Keep your deployment updated:

```bash
# Update Terraform modules
terraform init -upgrade

# Update Packer templates
packer init -upgrade jenkins-master.pkr.hcl

# Update Ansible roles
ansible-galaxy install -r requirements.yml --force
```

---

**Next Steps**: After successful deployment, proceed to [Monitoring Guide](monitoring-guide.md) and [Security Guide](security-guide.md).
