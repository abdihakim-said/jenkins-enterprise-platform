#!/bin/bash
# Jenkins Golden AMI User Data Script - Fixed Version

set -e

# Variables from Terraform
EFS_FILE_SYSTEM_ID="${efs_file_system_id}"
AWS_REGION="${aws_region}"
ENVIRONMENT="${environment}"

# Log everything
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "=== Jenkins Golden AMI User Data Started ==="
echo "EFS File System ID: $EFS_FILE_SYSTEM_ID"
echo "AWS Region: $AWS_REGION"
echo "Environment: $ENVIRONMENT"
echo "Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)"
echo "Timestamp: $(date)"

# Install missing packages
echo "=== Installing required packages ==="
apt update -y
apt install -y amazon-efs-utils

# Check if Jenkins user exists, create if not
if ! id "jenkins" &>/dev/null; then
    echo "Creating jenkins user..."
    useradd -r -m -s /bin/bash jenkins
fi

# Stop Jenkins if running to safely move data
systemctl stop jenkins || true

# Mount EFS if provided
if [ -n "$EFS_FILE_SYSTEM_ID" ]; then
    echo "=== Mounting EFS file system ==="
    
    # Create temporary mount point
    mkdir -p /mnt/efs-temp
    
    # Mount EFS temporarily to set up directories
    mount -t efs $EFS_FILE_SYSTEM_ID.efs.$AWS_REGION.amazonaws.com:/ /mnt/efs-temp
    
    if mountpoint -q /mnt/efs-temp; then
        echo "✅ EFS mounted successfully"
        
        # Create Jenkins directories on EFS
        mkdir -p /mnt/efs-temp/jenkins
        mkdir -p /mnt/efs-temp/workspace
        
        # Set proper ownership
        chown -R jenkins:jenkins /mnt/efs-temp/jenkins
        chown -R jenkins:jenkins /mnt/efs-temp/workspace
        
        # Unmount temporary mount
        umount /mnt/efs-temp
        
        # Create Jenkins home directory if it doesn't exist
        mkdir -p /var/lib/jenkins
        
        # Backup existing Jenkins data if any
        if [ -d /var/lib/jenkins ] && [ "$(ls -A /var/lib/jenkins)" ]; then
            echo "Backing up existing Jenkins data..."
            mv /var/lib/jenkins /var/lib/jenkins.backup.$(date +%s)
        fi
        
        # Create new Jenkins home directory
        mkdir -p /var/lib/jenkins
        mkdir -p /var/lib/jenkins/workspace
        
        # Add EFS mounts to fstab
        if ! grep -q "$EFS_FILE_SYSTEM_ID.*jenkins" /etc/fstab; then
            echo "$EFS_FILE_SYSTEM_ID.efs.$AWS_REGION.amazonaws.com:/jenkins /var/lib/jenkins efs defaults,_netdev,accesspoint=fsap-0d3b5b40f354f4bb9 0 0" >> /etc/fstab
            echo "$EFS_FILE_SYSTEM_ID.efs.$AWS_REGION.amazonaws.com:/workspace /var/lib/jenkins/workspace efs defaults,_netdev,accesspoint=fsap-09bbc067252dafab4 0 0" >> /etc/fstab
        fi
        
        # Mount EFS to Jenkins directories
        mount -a
        
        # Verify mounts
        if mountpoint -q /var/lib/jenkins && mountpoint -q /var/lib/jenkins/workspace; then
            echo "✅ Jenkins EFS directories mounted successfully"
            chown -R jenkins:jenkins /var/lib/jenkins
        else
            echo "❌ EFS mount to Jenkins directories failed"
        fi
    else
        echo "❌ EFS mount failed"
        # Ensure local directories exist as fallback
        mkdir -p /var/lib/jenkins
        mkdir -p /var/lib/jenkins/workspace
        chown -R jenkins:jenkins /var/lib/jenkins
    fi
else
    # Ensure Jenkins directories exist
    mkdir -p /var/lib/jenkins
    mkdir -p /var/lib/jenkins/workspace
    chown -R jenkins:jenkins /var/lib/jenkins
fi

# Ensure log directory exists
mkdir -p /var/log/jenkins
chown -R jenkins:jenkins /var/log/jenkins

# Start Jenkins service
echo "=== Starting Jenkins ==="
systemctl enable jenkins
systemctl start jenkins

# Wait for Jenkins to start
echo "=== Waiting for Jenkins to start ==="
timeout=600  # Increased timeout
counter=0
while [ $counter -lt $timeout ]; do
    if curl -s http://localhost:8080/login > /dev/null 2>&1; then
        echo "✅ Jenkins is running and responding"
        break
    fi
    echo "Waiting for Jenkins... ($counter/$timeout)"
    sleep 15
    counter=$((counter + 15))
done

if [ $counter -ge $timeout ]; then
    echo "❌ Jenkins failed to start within timeout"
    echo "Jenkins service status:"
    systemctl status jenkins --no-pager
    echo "Jenkins logs:"
    journalctl -u jenkins --no-pager -n 50
fi

# Final health check
echo "=== Final Health Check ==="
echo "Jenkins service status: $(systemctl is-active jenkins)"
echo "Jenkins process: $(pgrep -f jenkins || echo 'Not running')"
echo "Port 8080 status: $(netstat -tlnp | grep :8080 || echo 'Not listening')"
echo "Jenkins HTTP response: $(curl -s -o /dev/null -w '%%{http_code}' http://localhost:8080/login 2>/dev/null || echo 'Failed')"

# Install and configure CloudWatch agent
echo "=== Installing CloudWatch Agent ==="
if ! command -v /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl &> /dev/null; then
    wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
    dpkg -i amazon-cloudwatch-agent.deb
    rm -f amazon-cloudwatch-agent.deb
fi

# Configure CloudWatch agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'
{
    "agent": {
        "metrics_collection_interval": 60,
        "run_as_user": "cwagent"
    },
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/user-data.log",
                        "log_group_name": "/jenkins/dev/user-data",
                        "log_stream_name": "{instance_id}",
                        "timezone": "UTC"
                    },
                    {
                        "file_path": "/var/log/jenkins/jenkins.log",
                        "log_group_name": "/jenkins/dev/application",
                        "log_stream_name": "{instance_id}",
                        "timezone": "UTC"
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

echo "=== Jenkins Golden AMI User Data Completed ==="
echo "Timestamp: $(date)"
touch /var/log/user-data-completed
