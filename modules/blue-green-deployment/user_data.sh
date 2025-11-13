#!/bin/bash
# Enterprise Blue/Green Deployment User Data Script
# Configures Jenkins instance with deployment-specific settings

set -e

# Variables from Terraform
EFS_FILE_SYSTEM_ID="${efs_file_system_id}"
AWS_REGION="${aws_region}"
ENVIRONMENT="${environment}"
DEPLOYMENT_COLOR="${deployment_color}"
LOG_GROUP_NAME="${log_group_name}"
SNS_TOPIC_ARN="${sns_topic_arn}"
HEALTH_CHECK_URL="${health_check_url}"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$DEPLOYMENT_COLOR] $1" | tee -a /var/log/deployment.log
}

log "Starting $DEPLOYMENT_COLOR deployment configuration..."

# Update system
log "Updating system packages..."
apt-get update -y
apt-get upgrade -y

# Install CloudWatch agent if not present
if ! command -v /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl &> /dev/null; then
    log "Installing CloudWatch agent..."
    wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
    dpkg -i amazon-cloudwatch-agent.deb
fi

# Configure CloudWatch agent
log "Configuring CloudWatch agent..."
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << EOF
{
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/var/log/deployment.log",
                        "log_group_name": "$LOG_GROUP_NAME",
                        "log_stream_name": "{instance_id}-$DEPLOYMENT_COLOR-deployment"
                    },
                    {
                        "file_path": "/var/log/jenkins/jenkins.log",
                        "log_group_name": "$LOG_GROUP_NAME",
                        "log_stream_name": "{instance_id}-$DEPLOYMENT_COLOR-jenkins"
                    }
                ]
            }
        }
    },
    "metrics": {
        "namespace": "Jenkins/$ENVIRONMENT/$DEPLOYMENT_COLOR",
        "metrics_collected": {
            "cpu": {
                "measurement": ["cpu_usage_idle", "cpu_usage_iowait", "cpu_usage_user", "cpu_usage_system"],
                "metrics_collection_interval": 60
            },
            "disk": {
                "measurement": ["used_percent"],
                "metrics_collection_interval": 60,
                "resources": ["*"]
            },
            "mem": {
                "measurement": ["mem_used_percent"],
                "metrics_collection_interval": 60
            }
        }
    }
}
EOF

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s

# Install EFS utils if not present (fallback)
install_efs_utils() {
    echo "=== Installing EFS Utils ==="
    if ! command -v mount.efs &> /dev/null; then
        # Wait for package locks to be released
        local max_wait=300
        local wait_time=0
        while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
            if [ $wait_time -ge $max_wait ]; then
                echo "⚠️ Timeout waiting for package locks, killing blocking processes"
                pkill -f unattended-upgrade || true
                sleep 10
                break
            fi
            echo "Waiting for package locks... ($wait_time/$max_wait)"
            sleep 10
            wait_time=$((wait_time + 10))
        done
        
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
        echo "Stopping Jenkins for EFS mount..."
        systemctl stop jenkins
        sleep 5
    fi
    
    # Backup existing data if mount point exists and has content
    if [ -d "$mount_point" ] && [ "$(ls -A $mount_point 2>/dev/null)" ]; then
        echo "Backing up existing Jenkins data..."
        mkdir -p /tmp/jenkins-backup
        cp -r $mount_point/* /tmp/jenkins-backup/ 2>/dev/null || true
    fi
    
    # Create mount point
    mkdir -p $mount_point
    
    local mount_success=false
    
    # Method 1: NFS4 mount (most reliable)
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
    
    # Handle mount success/failure
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
        
        # Set proper ownership
        chown -R jenkins:jenkins $mount_point
        chmod 755 $mount_point
        rm -rf /tmp/jenkins-backup
        
        echo "✅ EFS mount successful"
    else
        echo "❌ All EFS mount methods failed, using local storage"
        mkdir -p $mount_point
        
        # Restore backup to local storage if available
        if [ -d "/tmp/jenkins-backup" ]; then
            echo "Restoring Jenkins data to local storage..."
            cp -r /tmp/jenkins-backup/* $mount_point/ 2>/dev/null || true
            rm -rf /tmp/jenkins-backup
        fi
        
        chown -R jenkins:jenkins $mount_point
        chmod 755 $mount_point
    fi
}

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

# Configure Jenkins for blue/green deployment
log "Configuring Jenkins for $DEPLOYMENT_COLOR deployment..."

# Create deployment-specific Jenkins configuration
mkdir -p /var/lib/jenkins/deployment
cat > /var/lib/jenkins/deployment/config.properties << EOF
deployment.color=$DEPLOYMENT_COLOR
deployment.environment=$ENVIRONMENT
deployment.timestamp=$(date '+%Y-%m-%d_%H-%M-%S')
health.check.url=$HEALTH_CHECK_URL
sns.topic.arn=$SNS_TOPIC_ARN
EOF

# Configure Jenkins system properties
JENKINS_OPTS="--httpPort=8080 --prefix=/jenkins"
JENKINS_OPTS="$JENKINS_OPTS -Djenkins.install.runSetupWizard=false"
JENKINS_OPTS="$JENKINS_OPTS -Dhudson.security.csrf.DefaultCrumbIssuer.EXCLUDE_SESSION_ID=true"
JENKINS_OPTS="$JENKINS_OPTS -Ddeployment.color=$DEPLOYMENT_COLOR"

echo "JENKINS_OPTS=\"$JENKINS_OPTS\"" > /etc/default/jenkins

# Create health check script
log "Creating health check script..."
cat > /usr/local/bin/health-check.sh << 'EOF'
#!/bin/bash
# Health check script for blue/green deployment

DEPLOYMENT_COLOR=$(cat /var/lib/jenkins/deployment/config.properties | grep deployment.color | cut -d'=' -f2)
HEALTH_CHECK_URL=$(cat /var/lib/jenkins/deployment/config.properties | grep health.check.url | cut -d'=' -f2)
SNS_TOPIC_ARN=$(cat /var/lib/jenkins/deployment/config.properties | grep sns.topic.arn | cut -d'=' -f2)

# Check Jenkins health
if curl -f -s "http://localhost:8080$HEALTH_CHECK_URL" > /dev/null; then
    echo "[$DEPLOYMENT_COLOR] Health check passed"
    # Send success notification
    aws sns publish --topic-arn "$SNS_TOPIC_ARN" --message "[$DEPLOYMENT_COLOR] Health check passed at $(date)"
    exit 0
else
    echo "[$DEPLOYMENT_COLOR] Health check failed"
    # Send failure notification
    aws sns publish --topic-arn "$SNS_TOPIC_ARN" --message "[$DEPLOYMENT_COLOR] Health check FAILED at $(date)"
    exit 1
fi
EOF

chmod +x /usr/local/bin/health-check.sh

# Create cron job for health checks
echo "*/2 * * * * root /usr/local/bin/health-check.sh >> /var/log/health-check.log 2>&1" > /etc/cron.d/jenkins-health-check

# Start Jenkins service
log "Starting Jenkins service..."
systemctl enable jenkins
systemctl start jenkins

# Wait for Jenkins to start
log "Waiting for Jenkins to start..."
timeout=300
counter=0
while ! curl -f -s http://localhost:8080/login > /dev/null; do
    if [ $counter -ge $timeout ]; then
        log "ERROR: Jenkins failed to start within $timeout seconds"
        exit 1
    fi
    sleep 5
    counter=$((counter + 5))
done

log "Jenkins started successfully"

# Configure deployment-specific settings
log "Applying deployment-specific configurations..."

# Set deployment color in Jenkins system info
mkdir -p /var/lib/jenkins/userContent
echo "<h2>Deployment: $DEPLOYMENT_COLOR Environment</h2>" > /var/lib/jenkins/userContent/deployment-info.html
echo "<p>Deployed at: $(date)</p>" >> /var/lib/jenkins/userContent/deployment-info.html

# Send deployment completion notification
aws sns publish --topic-arn "$SNS_TOPIC_ARN" --message "[$DEPLOYMENT_COLOR] Deployment completed successfully at $(date)"

log "$DEPLOYMENT_COLOR deployment configuration completed successfully"

# Final health check
/usr/local/bin/health-check.sh

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

log "User data script execution completed"
