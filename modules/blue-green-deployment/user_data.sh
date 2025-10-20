#!/bin/bash
# Enterprise Blue/Green Deployment User Data Script
# Configures Jenkins instance with deployment-specific settings

set -e

# Variables from Terraform
EFS_DNS_NAME="${efs_dns_name}"
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

# Mount EFS
log "Mounting EFS file system..."
mkdir -p /var/jenkins_home
echo "$EFS_DNS_NAME:/ /var/jenkins_home nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,intr,timeo=600 0 0" >> /etc/fstab
mount -a

# Set proper permissions
chown -R jenkins:jenkins /var/jenkins_home
chmod 755 /var/jenkins_home

# Configure Jenkins for blue/green deployment
log "Configuring Jenkins for $DEPLOYMENT_COLOR deployment..."

# Create deployment-specific Jenkins configuration
mkdir -p /var/jenkins_home/deployment
cat > /var/jenkins_home/deployment/config.properties << EOF
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

DEPLOYMENT_COLOR=$(cat /var/jenkins_home/deployment/config.properties | grep deployment.color | cut -d'=' -f2)
HEALTH_CHECK_URL=$(cat /var/jenkins_home/deployment/config.properties | grep health.check.url | cut -d'=' -f2)
SNS_TOPIC_ARN=$(cat /var/jenkins_home/deployment/config.properties | grep sns.topic.arn | cut -d'=' -f2)

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
mkdir -p /var/jenkins_home/userContent
echo "<h2>Deployment: $DEPLOYMENT_COLOR Environment</h2>" > /var/jenkins_home/userContent/deployment-info.html
echo "<p>Deployed at: $(date)</p>" >> /var/jenkins_home/userContent/deployment-info.html

# Send deployment completion notification
aws sns publish --topic-arn "$SNS_TOPIC_ARN" --message "[$DEPLOYMENT_COLOR] Deployment completed successfully at $(date)"

log "$DEPLOYMENT_COLOR deployment configuration completed successfully"

# Final health check
/usr/local/bin/health-check.sh

log "User data script execution completed"
