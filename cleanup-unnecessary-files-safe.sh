#!/bin/bash
# Safe Cleanup - Keep EFS Validation for Troubleshooting
# This keeps the EFS validation script for future debugging

echo "🧹 Safe cleanup of unnecessary pipeline files..."

# Remove duplicate Jenkinsfile (older version)
if [ -f "Jenkinsfile" ]; then
    echo "❌ Removing duplicate Jenkinsfile (use Jenkinsfile-golden-image instead)"
    rm "Jenkinsfile"
fi

# Keep EFS validation but move to scripts folder for troubleshooting
if [ -f "Jenkinsfile-efs-validation" ]; then
    echo "📁 Moving Jenkinsfile-efs-validation to scripts/ (for troubleshooting)"
    mv "Jenkinsfile-efs-validation" "scripts/efs-validation-pipeline"
fi

# Remove EFS health monitoring (CloudWatch does this)
if [ -f "Jenkinsfile-efs-health" ]; then
    echo "❌ Removing Jenkinsfile-efs-health (CloudWatch monitors this)"
    rm "Jenkinsfile-efs-health"
fi

# Remove old XML job definition
if [ -f "golden-ami-job.xml" ]; then
    echo "❌ Removing golden-ami-job.xml (replaced by Jenkinsfile-golden-image)"
    rm "golden-ami-job.xml"
fi

echo ""
echo "✅ Safe cleanup complete!"
echo ""
echo "📁 Production Pipelines:"
echo "   🚀 Jenkinsfile-golden-image (AMI building)"
echo "   🏗️  Jenkinsfile-infrastructure (Infrastructure deployment)"
echo ""
echo "🔧 Troubleshooting Tools:"
echo "   📋 scripts/efs-validation-pipeline (EFS testing)"
echo "   🔍 scripts/test-platform.sh (Full platform test)"
echo ""
