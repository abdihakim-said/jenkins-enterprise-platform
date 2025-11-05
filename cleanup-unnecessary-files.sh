#!/bin/bash
# Cleanup Unnecessary Pipeline Files
# Run this to remove duplicate and obsolete pipeline files

echo "🧹 Cleaning up unnecessary pipeline files..."

# Remove duplicate Jenkinsfile (older version)
if [ -f "Jenkinsfile" ]; then
    echo "❌ Removing duplicate Jenkinsfile (use Jenkinsfile-golden-image instead)"
    rm "Jenkinsfile"
fi

# Remove EFS validation files (one-time tests, not needed)
if [ -f "Jenkinsfile-efs-validation" ]; then
    echo "❌ Removing Jenkinsfile-efs-validation (one-time test, not needed)"
    rm "Jenkinsfile-efs-validation"
fi

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
echo "✅ Cleanup complete! Remaining pipeline files:"
echo "   📁 Jenkinsfile-golden-image (AMI building)"
echo "   📁 Jenkinsfile-infrastructure (Infrastructure deployment)"
echo ""
echo "These 2 files are all you need for production operations."
