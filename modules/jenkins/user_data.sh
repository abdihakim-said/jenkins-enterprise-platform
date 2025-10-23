#!/bin/bash
# Jenkins User Data - Runtime EFS Mount with Error Handling

set -e

# Variables from Terraform
EFS_FILE_SYSTEM_ID="${efs_file_system_id}"
AWS_REGION="${aws_region}"
ENVIRONMENT="${environment}"

# Log everything
exec > >(tee /var/log/user-data.log)
exec 2>&1

echo "=== Jenkins User Data Started ==="
echo "EFS ID: $EFS_FILE_SYSTEM_ID"
echo "Region: $AWS_REGION"
echo "Environment: $ENVIRONMENT"

# Install EFS utils if not present (fallback)
install_efs_utils() {
    echo "=== Installing EFS Utils ==="
    if ! command -v mount.efs &> /dev/null; then
        apt-get update -y
        apt-get install -y nfs-common
        echo "✅ NFS utils installed"
    else
        echo "✅ EFS utils already available"
    fi
}

# Enhanced EFS Mount Function with Error Handling
mount_efs() {
    local efs_id=$1
    local region=$2
    local mount_point="/var/lib/jenkins"
    
    echo "=== Mounting EFS with Error Handling ==="
    
    # Stop Jenkins safely
    if systemctl is-active --quiet jenkins; then
        echo "Stopping Jenkins service..."
        systemctl stop jenkins
        sleep 5
    fi
    
    # Backup existing data
    if [ -d "$mount_point" ] && [ "$(ls -A $mount_point 2>/dev/null)" ]; then
        echo "Backing up existing Jenkins data..."
        mkdir -p /tmp/jenkins-backup
        cp -r $mount_point/* /tmp/jenkins-backup/ 2>/dev/null || true
    fi
    
    # Create mount point
    mkdir -p $mount_point
    
    # Try multiple mount methods with error handling
    local mount_success=false
    
    # Method 1: NFS4 mount
    echo "Attempting NFS4 mount..."
    if timeout 30 mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 \
        $efs_id.efs.$region.amazonaws.com:/ $mount_point 2>/dev/null; then
        echo "✅ EFS mounted via NFS4"
        mount_success=true
    else
        echo "⚠️ NFS4 mount failed, trying EFS utils..."
        
        # Method 2: EFS utils mount
        if command -v mount.efs &> /dev/null; then
            if timeout 30 mount -t efs -o tls $efs_id:/ $mount_point 2>/dev/null; then
                echo "✅ EFS mounted via EFS utils"
                mount_success=true
            else
                echo "⚠️ EFS utils mount failed"
            fi
        else
            echo "⚠️ EFS utils not available"
        fi
    fi
    
    if [ "$mount_success" = true ]; then
        # Add to fstab for persistence
        if ! grep -q "$efs_id" /etc/fstab; then
            echo "$efs_id.efs.$region.amazonaws.com:/ $mount_point nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,_netdev 0 0" >> /etc/fstab
        fi
        
        # Restore data if EFS is empty
        if [ -d "/tmp/jenkins-backup" ] && [ -z "$(ls -A $mount_point 2>/dev/null)" ]; then
            echo "Restoring Jenkins data to EFS..."
            cp -r /tmp/jenkins-backup/* $mount_point/ 2>/dev/null || true
        fi
        
        # Cleanup backup
        rm -rf /tmp/jenkins-backup
        
        echo "✅ EFS mount successful"
    else
        echo "❌ All EFS mount methods failed, using local storage"
        mkdir -p $mount_point
        
        # Restore backup to local storage
        if [ -d "/tmp/jenkins-backup" ]; then
            echo "Restoring Jenkins data to local storage..."
            cp -r /tmp/jenkins-backup/* $mount_point/ 2>/dev/null || true
            rm -rf /tmp/jenkins-backup
        fi
        
        echo "⚠️ Jenkins will use local storage - data will not persist across instance replacements"
    fi
    
    # Set proper permissions
    chown -R jenkins:jenkins $mount_point
    chmod 755 $mount_point
}

# Create Jenkins user if needed
if ! id "jenkins" &>/dev/null; then
    echo "Creating Jenkins user..."
    useradd -r -m -s /bin/bash jenkins
fi

# Install EFS utils as fallback
install_efs_utils

# Mount EFS if provided
if [ -n "$EFS_FILE_SYSTEM_ID" ] && [ "$EFS_FILE_SYSTEM_ID" != "null" ]; then
    mount_efs "$EFS_FILE_SYSTEM_ID" "$AWS_REGION"
else
    echo "No EFS ID provided, using local storage"
    mkdir -p /var/lib/jenkins
    chown -R jenkins:jenkins /var/lib/jenkins
fi

# Ensure log directory exists
mkdir -p /var/log/jenkins
chown -R jenkins:jenkins /var/log/jenkins

# Start Jenkins service
echo "=== Starting Jenkins ==="
systemctl enable jenkins
systemctl start jenkins

# Wait for Jenkins to start with better error handling
echo "=== Waiting for Jenkins to start ==="
timeout=300
counter=0
jenkins_started=false

while [ $counter -lt $timeout ]; do
    if systemctl is-active --quiet jenkins; then
        if curl -s --connect-timeout 5 http://localhost:8080/login > /dev/null 2>&1; then
            echo "✅ Jenkins is running and responding"
            jenkins_started=true
            break
        fi
    fi
    echo "Waiting for Jenkins... ($counter/$timeout)"
    sleep 10
    counter=$((counter + 10))
done

if [ "$jenkins_started" = false ]; then
    echo "❌ Jenkins failed to start within timeout"
    echo "=== Diagnostics ==="
    echo "Jenkins service status:"
    systemctl status jenkins --no-pager || true
    echo "Jenkins logs (last 50 lines):"
    journalctl -u jenkins --no-pager -n 50 || true
    echo "Port 8080 status:"
    netstat -tlnp | grep :8080 || echo "Port 8080 not listening"
    echo "Jenkins process:"
    pgrep -f jenkins || echo "No Jenkins process found"
fi

# Final health check
echo "=== Final Health Check ==="
echo "Jenkins service status: $(systemctl is-active jenkins 2>/dev/null || echo 'inactive')"
echo "Jenkins process: $(pgrep -f jenkins 2>/dev/null || echo 'Not running')"
echo "Port 8080 status: $(netstat -tlnp 2>/dev/null | grep :8080 || echo 'Not listening')"
echo "Jenkins HTTP response: $(curl -s -o /dev/null -w '%%{http_code}' http://localhost:8080/login 2>/dev/null || echo 'Failed')"

# EFS mount verification
if [ -n "$EFS_FILE_SYSTEM_ID" ] && [ "$EFS_FILE_SYSTEM_ID" != "null" ]; then
    echo "=== EFS Mount Verification ==="
    if mountpoint -q /var/lib/jenkins; then
        echo "✅ EFS is mounted at /var/lib/jenkins"
        echo "Mount details: $(mount | grep /var/lib/jenkins)"
    else
        echo "⚠️ EFS is not mounted, using local storage"
    fi
fi

# Install and configure CloudWatch agent
echo "=== Installing CloudWatch Agent ==="
if ! command -v /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl &> /dev/null; then
    wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
    dpkg -i amazon-cloudwatch-agent.deb
    rm -f amazon-cloudwatch-agent.deb
fi

# Configure CloudWatch agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << EOF
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
                        "log_group_name": "/jenkins/${environment}/user-data",
                        "log_stream_name": "{instance_id}",
                        "timezone": "UTC"
                    },
                    {
                        "file_path": "/var/log/jenkins/jenkins.log",
                        "log_group_name": "/jenkins/${environment}/application",
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

echo "=== Jenkins User Data Completed ==="
echo "Timestamp: $(date)"
echo "Status: $([ "$jenkins_started" = true ] && echo "SUCCESS" || echo "PARTIAL - Jenkins may need manual intervention")"
touch /var/log/user-data-completed
