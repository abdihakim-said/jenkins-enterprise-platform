#!/bin/bash
# AMI Lifecycle Management - DevSecOps Automation
# Keeps only the latest 3 AMIs, deregisters older ones

set -e

PROJECT_NAME="jenkins-enterprise-platform"
ENVIRONMENT=${1:-"dev"}
MAX_AMIS=3

echo "🔄 Managing AMI lifecycle for ${PROJECT_NAME} (${ENVIRONMENT})"

# Get all Jenkins AMIs sorted by creation date (newest first)
AMIS=$(aws ec2 describe-images \
    --owners self \
    --filters "Name=name,Values=jenkins-golden-ami-*" \
              "Name=tag:Environment,Values=${ENVIRONMENT}" \
              "Name=state,Values=available" \
    --query 'Images[*].[ImageId,CreationDate,Name]' \
    --output text | sort -k2 -r)

echo "Found AMIs:"
echo "$AMIS"

# Count total AMIs
TOTAL_AMIS=$(echo "$AMIS" | wc -l)
echo "Total AMIs: $TOTAL_AMIS"

if [ $TOTAL_AMIS -gt $MAX_AMIS ]; then
    echo "🗑️ Cleaning up old AMIs (keeping latest $MAX_AMIS)"
    
    # Get AMIs to delete (skip first MAX_AMIS)
    AMIS_TO_DELETE=$(echo "$AMIS" | tail -n +$((MAX_AMIS + 1)) | awk '{print $1}')
    
    for AMI_ID in $AMIS_TO_DELETE; do
        echo "Deregistering AMI: $AMI_ID"
        
        # Get snapshot ID before deregistering
        SNAPSHOT_ID=$(aws ec2 describe-images \
            --image-ids $AMI_ID \
            --query 'Images[0].BlockDeviceMappings[0].Ebs.SnapshotId' \
            --output text)
        
        # Deregister AMI
        aws ec2 deregister-image --image-id $AMI_ID
        
        # Delete associated snapshot
        if [ "$SNAPSHOT_ID" != "None" ] && [ "$SNAPSHOT_ID" != "" ]; then
            echo "Deleting snapshot: $SNAPSHOT_ID"
            aws ec2 delete-snapshot --snapshot-id $SNAPSHOT_ID
        fi
    done
    
    echo "✅ AMI cleanup completed"
else
    echo "✅ No cleanup needed (${TOTAL_AMIS} <= ${MAX_AMIS})"
fi
