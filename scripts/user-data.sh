#!/bin/bash

# Jenkins Enterprise Platform - User Data Script
# Updated with Java 17 and Best Practices
# Date: 2025-08-17
# Version: 2.0

set -e  # Exit on any error

# Logging setup
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "=== Jenkins Enterprise Platform Setup Started at $(date) ==="

# Update system packages
echo "=== Updating system packages ==="
apt-get update -y
apt-get upgrade -y

# Install essential packages
echo "=== Installing essential packages ==="
apt-get install -y \
    curl \
    wget \
    gnupg2 \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    lsb-release \
    unzip \
    jq \
    htop \
    vim \
    git \
    nfs-common \
    awscli \
    python3-pip \
    docker.io \
    prometheus-node-exporter

# Install Java 17 (Required for Jenkins 2.516.1+)
echo "=== Installing Java 17 for Jenkins ==="
apt-get install -y openjdk-17-jdk

# Verify Java installation
java -version
echo "JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64" >> /etc/environment
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64

# Add Jenkins repository and install Jenkins
echo "=== Installing Jenkins ==="
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/ | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
apt-get update -y
apt-get install -y jenkins

# Configure Jenkins user for sudo access (Security requirement)
echo "=== Configuring Jenkins user permissions ==="
usermod -aG sudo jenkins
echo "jenkins ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/jenkins

# Install and configure Docker for Jenkins
echo "=== Configuring Docker for Jenkins ==="
systemctl enable docker
systemctl start docker
usermod -aG docker jenkins

# Install AWS CLI v2 (Latest version)
echo "=== Installing AWS CLI v2 ==="
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

# Install Terraform (for IaC pipelines)
echo "=== Installing Terraform ==="
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
apt-get update -y
apt-get install -y terraform

# Install Ansible (for configuration management)
echo "=== Installing Ansible ==="
pip3 install ansible boto3 botocore

# Install Packer (for AMI building)
echo "=== Installing Packer ==="
apt-get install -y packer

# Install Trivy (for security scanning)
echo "=== Installing Trivy for security scanning ==="
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | apt-key add -
echo "deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | tee -a /etc/apt/sources.list.d/trivy.list
apt-get update -y
apt-get install -y trivy

# Configure EFS mount point (for Jenkins data persistence)
echo "=== Configuring EFS mount point ==="
mkdir -p /var/lib/jenkins-efs
mkdir -p /mnt/efs

# Get EFS ID from instance metadata or parameter store
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
EFS_ID=$(aws ssm get-parameter --name "/jenkins/efs-id" --region $REGION --query 'Parameter.Value' --output text 2>/dev/null || echo "")

if [ ! -z "$EFS_ID" ]; then
    echo "=== Mounting EFS: $EFS_ID ==="
    echo "$EFS_ID.efs.$REGION.amazonaws.com:/ /mnt/efs nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,intr,timeo=600 0 0" >> /etc/fstab
    mount -a
    
    # Setup Jenkins data directory on EFS
    if [ ! -d "/mnt/efs/jenkins" ]; then
        mkdir -p /mnt/efs/jenkins
        chown jenkins:jenkins /mnt/efs/jenkins
    fi
    
    # Create symlink for Jenkins home
    systemctl stop jenkins || true
    if [ -d "/var/lib/jenkins" ]; then
        cp -r /var/lib/jenkins/* /mnt/efs/jenkins/ 2>/dev/null || true
        rm -rf /var/lib/jenkins
    fi
    ln -s /mnt/efs/jenkins /var/lib/jenkins
    chown -h jenkins:jenkins /var/lib/jenkins
fi

# Configure Jenkins service
echo "=== Configuring Jenkins service ==="
systemctl enable jenkins

# Configure Jenkins JVM options for performance
echo "=== Configuring Jenkins JVM options ==="
mkdir -p /etc/systemd/system/jenkins.service.d
cat > /etc/systemd/system/jenkins.service.d/override.conf << EOF
[Service]
Environment="JAVA_OPTS=-Djava.awt.headless=true -Xmx4g -Xms2g -XX:+UseG1GC -XX:+UseStringDeduplication"
Environment="JENKINS_OPTS=--httpPort=8080 --prefix="
EOF

# Install Jenkins plugins for monitoring and security
echo "=== Preparing Jenkins plugins configuration ==="
mkdir -p /var/lib/jenkins/plugins
cat > /tmp/jenkins-plugins.txt << EOF
prometheus:2.0.11
build-monitor-plugin:1.12+build.201809061734
monitoring:1.95.0
aws-credentials:191.vcb_f183ce58b_9
pipeline-stage-view:2.25
blueocean:1.25.2
role-strategy:546.vd4a_6759b_7c04
matrix-auth:3.1.5
configuration-as-code:1625.v27444588cc3d
workflow-aggregator:590.v6a_d052e5a_a_b_5
git:4.13.0
github:1.37.0
docker-workflow:563.vd5d2e5c4007f
ansible:204.v8191fd75b_fcd
terraform:1.0.10
EOF

# Configure CloudWatch agent for monitoring
echo "=== Installing CloudWatch agent ==="
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i amazon-cloudwatch-agent.deb
rm amazon-cloudwatch-agent.deb

# CloudWatch agent configuration
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << EOF
{
    "agent": {
        "metrics_collection_interval": 60,
        "run_as_user": "cwagent"
    },
    "metrics": {
        "namespace": "Jenkins/EC2",
        "metrics_collected": {
            "cpu": {
                "measurement": [
                    "cpu_usage_idle",
                    "cpu_usage_iowait",
                    "cpu_usage_user",
                    "cpu_usage_system"
                ],
                "metrics_collection_interval": 60,
                "totalcpu": false
            },
            "disk": {
                "measurement": [
                    "used_percent"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ]
            },
            "diskio": {
                "measurement": [
                    "io_time"
                ],
                "metrics_collection_interval": 60,
                "resources": [
                    "*"
                ]
            },
            "mem": {
                "measurement": [
                    "mem_used_percent"
                ],
                "metrics_collection_interval": 60
            }
        }
    },
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/jenkins/jenkins.log",
                        "log_group_name": "/aws/ec2/jenkins",
                        "log_stream_name": "{instance_id}/jenkins.log"
                    },
                    {
                        "file_path": "/var/log/user-data.log",
                        "log_group_name": "/aws/ec2/jenkins",
                        "log_stream_name": "{instance_id}/user-data.log"
                    }
                ]
            }
        }
    }
}
EOF

# Configure Prometheus Node Exporter
echo "=== Configuring Prometheus Node Exporter ==="
systemctl enable prometheus-node-exporter
systemctl start prometheus-node-exporter

# Security hardening
echo "=== Applying security hardening ==="
# Disable root login
sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config

# Configure firewall (UFW)
ufw --force enable
ufw allow 22/tcp    # SSH
ufw allow 8080/tcp  # Jenkins
ufw allow 9100/tcp  # Node Exporter

# Set up log rotation for Jenkins
cat > /etc/logrotate.d/jenkins << EOF
/var/log/jenkins/jenkins.log {
    daily
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 644 jenkins jenkins
    postrotate
        systemctl reload jenkins > /dev/null 2>&1 || true
    endscript
}
EOF

# Create backup script for Jenkins
echo "=== Creating Jenkins backup script ==="
cat > /usr/local/bin/jenkins-backup.sh << 'EOF'
#!/bin/bash
# Jenkins Backup Script
BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/tmp/jenkins-backup-$BACKUP_DATE"
S3_BUCKET="jenkins-backup-$(curl -s http://169.254.169.254/latest/meta-data/instance-id)"

mkdir -p $BACKUP_DIR
tar -czf $BACKUP_DIR/jenkins-home.tar.gz -C /var/lib/jenkins .
aws s3 cp $BACKUP_DIR/jenkins-home.tar.gz s3://$S3_BUCKET/jenkins-backup-$BACKUP_DATE.tar.gz
rm -rf $BACKUP_DIR
echo "Jenkins backup completed: jenkins-backup-$BACKUP_DATE.tar.gz"
EOF

chmod +x /usr/local/bin/jenkins-backup.sh

# Create cron job for daily backups
echo "0 2 * * * jenkins /usr/local/bin/jenkins-backup.sh" | crontab -u jenkins -

# Configure Jenkins initial setup
echo "=== Configuring Jenkins initial setup ==="
systemctl daemon-reload
systemctl start jenkins

# Wait for Jenkins to start
echo "=== Waiting for Jenkins to start ==="
timeout=300
counter=0
while ! curl -s http://localhost:8080/login > /dev/null; do
    if [ $counter -ge $timeout ]; then
        echo "Jenkins failed to start within $timeout seconds"
        exit 1
    fi
    echo "Waiting for Jenkins to start... ($counter/$timeout)"
    sleep 10
    counter=$((counter + 10))
done

# Install Jenkins plugins
echo "=== Installing Jenkins plugins ==="
JENKINS_CLI="/var/lib/jenkins/jenkins-cli.jar"
wget -O $JENKINS_CLI http://localhost:8080/jnlpJars/jenkins-cli.jar

# Get initial admin password
ADMIN_PASSWORD=$(cat /var/lib/jenkins/secrets/initialAdminPassword)

# Install plugins
while read plugin; do
    java -jar $JENKINS_CLI -s http://localhost:8080 -auth admin:$ADMIN_PASSWORD install-plugin $plugin
done < /tmp/jenkins-plugins.txt

# Restart Jenkins to load plugins
systemctl restart jenkins

# Wait for Jenkins to restart
sleep 30
while ! curl -s http://localhost:8080/login > /dev/null; do
    echo "Waiting for Jenkins to restart..."
    sleep 10
done

# Start CloudWatch agent
echo "=== Starting CloudWatch agent ==="
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config \
    -m ec2 \
    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
    -s

# Final system cleanup
echo "=== Performing final cleanup ==="
apt-get autoremove -y
apt-get autoclean

# Create status file
echo "=== Creating deployment status ==="
cat > /var/lib/jenkins/deployment-status.json << EOF
{
    "deployment_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "jenkins_version": "$(jenkins --version 2>/dev/null || echo 'unknown')",
    "java_version": "$(java -version 2>&1 | head -n 1)",
    "instance_id": "$(curl -s http://169.254.169.254/latest/meta-data/instance-id)",
    "region": "$(curl -s http://169.254.169.254/latest/meta-data/placement/region)",
    "status": "completed"
}
EOF

echo "=== Jenkins Enterprise Platform Setup Completed at $(date) ==="
echo "=== Initial Admin Password: $(cat /var/lib/jenkins/secrets/initialAdminPassword) ==="
echo "=== Jenkins URL: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8080 ==="

# Signal successful completion
/opt/aws/bin/cfn-signal -e $? --stack ${AWS::StackName} --resource AutoScalingGroup --region ${AWS::Region} 2>/dev/null || true

exit 0
