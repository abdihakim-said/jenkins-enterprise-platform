#!/bin/bash

# Cleanup script for duplicate VPC resources
# Target VPC: vpc-0bc95d2e508c6b4c1 (tagged as "Learning Environment")

VPC_ID="vpc-0bc95d2e508c6b4c1"
SUBNETS=(
    "subnet-01032b58f0add41de"
    "subnet-0ba086af1699a99b1" 
    "subnet-021eaaa70d4ee82e3"
    "subnet-051f0db333cfe35ca"
    "subnet-0779580fb525a9921"
    "subnet-06582b70892ea7131"
)

echo "🧹 Starting cleanup of duplicate VPC: $VPC_ID"

# Delete subnets first
for subnet in "${SUBNETS[@]}"; do
    echo "Deleting subnet: $subnet"
    aws ec2 delete-subnet --subnet-id "$subnet" --region us-east-1
    if [ $? -eq 0 ]; then
        echo "✅ Deleted subnet: $subnet"
    else
        echo "❌ Failed to delete subnet: $subnet"
    fi
done

# Wait a moment for AWS to process
sleep 5

# Delete the VPC
echo "Deleting VPC: $VPC_ID"
aws ec2 delete-vpc --vpc-id "$VPC_ID" --region us-east-1
if [ $? -eq 0 ]; then
    echo "✅ Deleted VPC: $VPC_ID"
else
    echo "❌ Failed to delete VPC: $VPC_ID"
fi

echo "🎉 Cleanup completed!"
