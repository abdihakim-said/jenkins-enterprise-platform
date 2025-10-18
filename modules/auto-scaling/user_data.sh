#!/bin/bash
#---------------------------------------------#
# Jenkins Enterprise Platform - User Data Script
# Author: Abdihakim Said
#---------------------------------------------#

set -euo pipefail

# Logging
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
echo "Starting Jenkins instance initialization..."

# Update system
apt-get update -y
apt-get upgrade -y

# Install required packages
apt-get install -y \
    openjdk-11-jdk \
    nfs-common \
    awscli \
    curl \
    wget \
    unzip

# Set JAVA_HOME
echo 'JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64' >> /etc/environment
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64

# Create Jenkins user
useradd -r -m -s /bin/bash jenkins
usermod -aG sudo jenkins

# Create Jenkins home directory
mkdir -p /var/lib/jenkins
chown jenkins:jenkins /var/lib/jenkins

# Mount EFS
echo "${efs_id}.efs.$(curl -s http://169.254.169.254/latest/meta-data/placement/region).amazonaws.com:/ /var/lib/jenkins nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 0 0" >> /etc/fstab
mount -a

# Install Jenkins
wget -q -O - https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | apt-key add -
echo "deb https://pkg.jenkins.io/debian-stable binary/" > /etc/apt/sources.list.d/jenkins.list
apt-get update -y
apt-get install -y jenkins

# Configure Jenkins
systemctl enable jenkins
systemctl start jenkins

# Install CloudWatch agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i amazon-cloudwatch-agent.deb

# Configure CloudWatch agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
{
    "metrics": {
        "namespace": "Jenkins/Metrics",
        "metrics_collected": {
            "cpu": {
                "measurement": [
                    "cpu_usage_idle",
                    "cpu_usage_iowait",
                    "cpu_usage_user",
                    "cpu_usage_system"
                ],
                "metrics_collection_interval": 60
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
                        "log_group_name": "/jenkins/${environment}/application",
                        "log_stream_name": "{instance_id}"
                    }
                ]
            }
        }
    }
}
EOF

# Start CloudWatch agent
systemctl enable amazon-cloudwatch-agent
systemctl start amazon-cloudwatch-agent

# Wait for Jenkins to start
sleep 60

# Get initial admin password
JENKINS_PASSWORD=$(cat /var/lib/jenkins/secrets/initialAdminPassword 2>/dev/null || echo "")
if [[ -n "$JENKINS_PASSWORD" ]]; then
    echo "Jenkins initial admin password: $JENKINS_PASSWORD"
    
    # Store password in SSM Parameter Store
    aws ssm put-parameter \
        --name "/jenkins/${environment}/admin-password" \
        --value "$JENKINS_PASSWORD" \
        --type "SecureString" \
        --overwrite \
        --region $(curl -s http://169.254.169.254/latest/meta-data/placement/region) || true
fi

echo "Jenkins instance initialization completed successfully!"
