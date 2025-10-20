#!/bin/bash
# Zero-Touch Golden AMI Pipeline Deployment

set -e

JENKINS_URL="http://dev-jenkins-alb-121130223.us-east-1.elb.amazonaws.com:8080"
JENKINS_USER="admin"
JENKINS_PASSWORD=$(aws ssm get-parameter --name "/jenkins/staging/admin-password" --with-decryption --query "Parameter.Value" --output text --region us-east-1)

echo "🚀 Zero-Touch Golden AMI Pipeline Deployment"
echo "============================================"

# Get Jenkins crumb for CSRF protection
echo "🔐 Getting Jenkins authentication..."
CRUMB=$(curl -s "$JENKINS_URL/crumbIssuer/api/json" --user "$JENKINS_USER:$JENKINS_PASSWORD" | python3 -c "import sys, json; data=json.load(sys.stdin); print(f'{data[\"crumbRequestField\"]}:{data[\"crumb\"]}')")

# Create Jenkins job via API
echo "📝 Creating Golden AMI Pipeline job..."
curl -s -X POST "$JENKINS_URL/createItem?name=Golden-AMI-Pipeline" \
  --user "$JENKINS_USER:$JENKINS_PASSWORD" \
  --header "$CRUMB" \
  --header "Content-Type: application/xml" \
  --data-binary @- << 'EOF'
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job">
  <description>Zero-Touch Golden AMI Pipeline</description>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition">
    <scm class="hudson.plugins.git.GitSCM">
      <userRemoteConfigs>
        <hudson.plugins.git.UserRemoteConfig>
          <url>.</url>
        </hudson.plugins.git.UserRemoteConfig>
      </userRemoteConfigs>
      <branches>
        <hudson.plugins.git.BranchSpec>
          <name>*/main</name>
        </hudson.plugins.git.BranchSpec>
      </branches>
    </scm>
    <scriptPath>Jenkinsfile-golden-image</scriptPath>
  </definition>
</flow-definition>
EOF

echo "🔥 Triggering Golden AMI Pipeline..."
curl -s -X POST "$JENKINS_URL/job/Golden-AMI-Pipeline/build" \
  --user "$JENKINS_USER:$JENKINS_PASSWORD" \
  --header "$CRUMB"

echo ""
echo "✅ Zero-touch deployment initiated!"
echo "🌐 Monitor at: $JENKINS_URL/job/Golden-AMI-Pipeline/"
echo "📋 Pipeline will execute Jenkinsfile-golden-image"
echo "⏱️  Expected completion: ~30 minutes"
echo ""
echo "🎯 Pipeline stages:"
echo "   1. Build Golden AMI with Packer"
echo "   2. Security scanning with Trivy"
echo "   3. End-to-end testing"
echo "   4. Infrastructure updates"
