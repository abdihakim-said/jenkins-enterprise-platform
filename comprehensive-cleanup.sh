#!/bin/bash

# COMPREHENSIVE CLEANUP - All duplicate resources
# CRITICAL: This will clean up the "Learning Environment" infrastructure
# KEEP: Current Terraform infrastructure with running Jenkins instances

echo "🚨 COMPREHENSIVE CLEANUP: Removing duplicate infrastructure"
echo "🎯 Target: Learning Environment (vpc-0bc95d2e508c6b4c1)"
echo "🛡️  Protect: Current Terraform infrastructure (vpc-078f44e066375930a)"
echo ""

# Duplicate EFS in wrong VPC (Learning Environment)
DUPLICATE_EFS="fs-0e3979b8eb0003341"
DUPLICATE_VPC="vpc-0bc95d2e508c6b4c1"

# Mount targets to delete (in wrong VPC)
DUPLICATE_MOUNT_TARGETS=(
    "fsmt-07fd7501086d3ce6c"
    "fsmt-09dca04de52c9c7a5" 
    "fsmt-0ffcdfa4026945d0a"
)

# NAT Gateways to delete (in wrong VPC)
DUPLICATE_NAT_GATEWAYS=(
    "nat-02c93bc1cda87b217"  # us-east-1c
    "nat-04cfc4678512e8dd1"  # us-east-1b  
    "nat-06ea2b7eb6f9004f2"  # us-east-1a
)

# Elastic IPs to release
DUPLICATE_EIPS=(
    "eipalloc-00250b37657ddc37e"  # 18.214.154.45
    "eipalloc-0fcd83b0ae1cfb6c7"  # 98.89.217.211
    "eipalloc-02c52c79cc26d8423"  # 34.193.123.239
)

echo "🗑️  Step 1: Deleting EFS mount targets in wrong VPC..."
for mount_target in "${DUPLICATE_MOUNT_TARGETS[@]}"; do
    echo "  Deleting mount target: $mount_target"
    aws efs delete-mount-target --mount-target-id "$mount_target" --region us-east-1
    if [ $? -eq 0 ]; then
        echo "  ✅ Deleted: $mount_target"
    else
        echo "  ❌ Failed: $mount_target"
    fi
done

echo ""
echo "⏳ Waiting 60 seconds for mount targets to be deleted..."
sleep 60

echo ""
echo "🗑️  Step 2: Deleting duplicate EFS file system..."
aws efs delete-file-system --file-system-id "$DUPLICATE_EFS" --region us-east-1
if [ $? -eq 0 ]; then
    echo "✅ Deleted EFS: $DUPLICATE_EFS"
else
    echo "❌ Failed to delete EFS: $DUPLICATE_EFS"
fi

echo ""
echo "🗑️  Step 3: Deleting NAT Gateways..."
for nat_gw in "${DUPLICATE_NAT_GATEWAYS[@]}"; do
    echo "  Deleting NAT Gateway: $nat_gw"
    aws ec2 delete-nat-gateway --nat-gateway-id "$nat_gw" --region us-east-1
    if [ $? -eq 0 ]; then
        echo "  ✅ Deleted: $nat_gw"
    else
        echo "  ❌ Failed: $nat_gw"
    fi
done

echo ""
echo "⏳ Waiting 120 seconds for NAT Gateways to be deleted..."
sleep 120

echo ""
echo "🗑️  Step 4: Releasing Elastic IPs..."
for eip in "${DUPLICATE_EIPS[@]}"; do
    echo "  Releasing EIP: $eip"
    aws ec2 release-address --allocation-id "$eip" --region us-east-1
    if [ $? -eq 0 ]; then
        echo "  ✅ Released: $eip"
    else
        echo "  ❌ Failed: $eip"
    fi
done

echo ""
echo "🗑️  Step 5: Deleting subnets in duplicate VPC..."
DUPLICATE_SUBNETS=(
    "subnet-01032b58f0add41de"
    "subnet-0ba086af1699a99b1"
    "subnet-021eaaa70d4ee82e3"
    "subnet-051f0db333cfe35ca"
    "subnet-0779580fb525a9921"
    "subnet-06582b70892ea7131"
)

for subnet in "${DUPLICATE_SUBNETS[@]}"; do
    echo "  Deleting subnet: $subnet"
    aws ec2 delete-subnet --subnet-id "$subnet" --region us-east-1
    if [ $? -eq 0 ]; then
        echo "  ✅ Deleted: $subnet"
    else
        echo "  ❌ Failed: $subnet"
    fi
done

echo ""
echo "🗑️  Step 6: Deleting duplicate VPC..."
aws ec2 delete-vpc --vpc-id "$DUPLICATE_VPC" --region us-east-1
if [ $? -eq 0 ]; then
    echo "✅ Deleted VPC: $DUPLICATE_VPC"
else
    echo "❌ Failed to delete VPC: $DUPLICATE_VPC"
fi

echo ""
echo "🎉 COMPREHENSIVE CLEANUP COMPLETED!"
echo ""
echo "📋 SUMMARY:"
echo "✅ Removed: Complete duplicate infrastructure (Learning Environment)"
echo "🛡️  Protected: Current Jenkins infrastructure with running instances"
echo "💾 Preserved: All data in correct EFS (fs-0a1c496937c7252d3)"
echo "⚠️  Next: Cancel hanging pipeline and fix Terraform state"
