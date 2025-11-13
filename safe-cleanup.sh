#!/bin/bash

# SAFE CLEANUP - Only resources created by today's hanging pipeline
# Date: 2025-11-12
# Time: 10:46:15-16 (when S3 buckets were created)

echo "🧹 SAFE CLEANUP: Only removing resources created by today's hanging pipeline"
echo "📅 Target: Resources created on 2025-11-12 between 10:46:15-16"

# S3 Buckets created by the hanging pipeline
PIPELINE_S3_BUCKETS=(
    "dev-jenkins-alb-logs-0tp92gw9"
    "dev-jenkins-cloudtrail-9dl5izve"
)

echo ""
echo "🗑️  Deleting S3 buckets created by hanging pipeline..."

for bucket in "${PIPELINE_S3_BUCKETS[@]}"; do
    echo "Checking bucket: $bucket"
    
    # Check if bucket exists and was created today
    CREATION_DATE=$(aws s3api head-bucket --bucket "$bucket" 2>/dev/null && aws s3api list-buckets --query "Buckets[?Name=='$bucket'].CreationDate" --output text)
    
    if [[ $CREATION_DATE == *"2025-11-12"* ]]; then
        echo "✅ Confirmed: $bucket was created today"
        
        # Empty bucket first
        echo "  Emptying bucket contents..."
        aws s3 rm s3://$bucket --recursive --quiet
        
        # Delete bucket
        echo "  Deleting bucket..."
        aws s3api delete-bucket --bucket "$bucket" --region us-east-1
        
        if [ $? -eq 0 ]; then
            echo "  ✅ Successfully deleted: $bucket"
        else
            echo "  ❌ Failed to delete: $bucket"
        fi
    else
        echo "  ⚠️  Skipping: $bucket (not created today or doesn't exist)"
    fi
    echo ""
done

echo "🎉 Safe cleanup completed!"
echo ""
echo "📋 SUMMARY:"
echo "✅ Deleted: Only S3 buckets created by today's hanging pipeline"
echo "🛡️  Protected: All existing infrastructure (VPCs, instances, EFS, etc.)"
echo "⚠️  Note: The hanging pipeline should be cancelled manually in Jenkins"
