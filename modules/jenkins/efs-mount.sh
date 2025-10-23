#!/bin/bash
# Automated EFS Mount Script with Fallback

set -e

EFS_ID="${efs_file_system_id}"
AWS_REGION="${aws_region}"
MOUNT_POINT="/var/lib/jenkins"

echo "=== Starting Automated EFS Mount ==="

# Function to mount EFS
mount_efs() {
    local method=$1
    echo "Trying EFS mount method: $method"
    
    case $method in
        "nfs4")
            mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 \
                $EFS_ID.efs.$AWS_REGION.amazonaws.com:/ $MOUNT_POINT
            ;;
        "efs")
            mount -t efs -o tls $EFS_ID:/ $MOUNT_POINT
            ;;
    esac
}

# Stop Jenkins
systemctl stop jenkins || true

# Backup existing data
if [ -d "$MOUNT_POINT" ] && [ "$(ls -A $MOUNT_POINT)" ]; then
    echo "Backing up existing Jenkins data..."
    mkdir -p /tmp/jenkins-backup
    cp -r $MOUNT_POINT/* /tmp/jenkins-backup/ 2>/dev/null || true
fi

# Create mount point
mkdir -p $MOUNT_POINT

# Try mounting with fallback
if mount_efs "nfs4"; then
    echo "✅ EFS mounted successfully via NFS4"
elif mount_efs "efs"; then
    echo "✅ EFS mounted successfully via EFS utils"
else
    echo "❌ EFS mount failed, using local storage"
    mkdir -p $MOUNT_POINT
fi

# Restore data if EFS is empty
if [ -d "/tmp/jenkins-backup" ] && [ -z "$(ls -A $MOUNT_POINT)" ]; then
    echo "Restoring Jenkins data to EFS..."
    cp -r /tmp/jenkins-backup/* $MOUNT_POINT/ 2>/dev/null || true
    rm -rf /tmp/jenkins-backup
fi

# Set permissions
chown -R jenkins:jenkins $MOUNT_POINT

# Add to fstab for persistence
if ! grep -q "$EFS_ID" /etc/fstab; then
    echo "$EFS_ID.efs.$AWS_REGION.amazonaws.com:/ $MOUNT_POINT nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 0 0" >> /etc/fstab
fi

# Start Jenkins
systemctl start jenkins

echo "=== EFS Mount Automation Complete ==="
