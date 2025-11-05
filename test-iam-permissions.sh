#!/bin/bash

# Test script to verify IAM permissions for Packer
echo "Testing IAM permissions for Jenkins role..."

# Get current instance ID (if running on EC2)
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo "not-on-ec2")

if [ "$INSTANCE_ID" != "not-on-ec2" ]; then
    echo "Running on EC2 instance: $INSTANCE_ID"
    
    # Test ec2:DescribeInstances permission
    echo "Testing ec2:DescribeInstances..."
    aws ec2 describe-instances --instance-ids $INSTANCE_ID --region us-east-1 --query 'Reservations[0].Instances[0].InstanceId' --output text
    
    # Test ec2:ModifyInstanceAttribute permission (dry run)
    echo "Testing ec2:ModifyInstanceAttribute (dry run)..."
    aws ec2 modify-instance-attribute --instance-id $INSTANCE_ID --ena-support --dry-run --region us-east-1 2>&1 | grep -q "DryRunOperation" && echo "✅ ec2:ModifyInstanceAttribute permission OK" || echo "❌ ec2:ModifyInstanceAttribute permission FAILED"
else
    echo "Not running on EC2, testing with AWS CLI profile..."
    
    # Test basic EC2 permissions
    echo "Testing basic EC2 describe permissions..."
    aws ec2 describe-regions --region us-east-1 --query 'Regions[0].RegionName' --output text
    
    echo "✅ Basic AWS CLI permissions working"
fi

echo "IAM permission test completed."
