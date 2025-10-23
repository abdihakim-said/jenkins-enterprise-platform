#!/bin/bash
# Golden AMI - EFS Preparation (Environment Agnostic)

set -e

echo "=== Preparing EFS Capabilities ==="

# Install NFS client
sudo apt install -y nfs-common

# Test NFS capability
mount.nfs4 --version

echo "✅ EFS capabilities prepared"
