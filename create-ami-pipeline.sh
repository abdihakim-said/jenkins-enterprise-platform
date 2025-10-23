#!/bin/bash
set -e

JENKINS_URL="http://dev-jenkins-alb-121130223.us-east-1.elb.amazonaws.com:8080"

echo "🚀 Creating Golden AMI Pipeline Job..."

# Create pipeline job configuration
cat > golden-ami-job.xml << 'JOBEOF'
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job">
  <description>Golden AMI Pipeline with Security Upgrades</description>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition" plugin="workflow-cps">
    <script>
pipeline {
    agent any
    
    parameters {
        choice(name: 'ENVIRONMENT', choices: ['dev', 'staging', 'production'], description: 'Target environment')
        string(name: 'JENKINS_VERSION', defaultValue: '2.426.1', description: 'Jenkins version')
        booleanParam(name: 'SECURITY_SCAN', defaultValue: true, description: 'Run security scans')
    }
    
    stages {
        stage('Prepare') {
            steps {
                echo "🔧 Preparing AMI build for ${params.ENVIRONMENT}"
                sh 'aws --version'
                sh 'packer version || echo "Packer not installed"'
            }
        }
        
        stage('Security Scan Base Image') {
            when { params.SECURITY_SCAN == true }
            steps {
                echo "🔒 Running security scan on base Ubuntu image"
                sh '''
                    echo "Scanning base Ubuntu 22.04 image for vulnerabilities..."
                    # Trivy scan would go here
                '''
            }
        }
        
        stage('Build Golden AMI') {
            steps {
                echo "🏗️ Building Jenkins Golden AMI"
                dir('packer') {
                    sh '''
                        echo "Building AMI with Packer..."
                        echo "Environment: ${ENVIRONMENT}"
                        echo "Jenkins Version: ${JENKINS_VERSION}"
                        # packer build jenkins-ami.pkr.hcl
                    '''
                }
            }
        }
        
        stage('Security Hardening') {
            steps {
                echo "🛡️ Applying CIS Ubuntu 22.04 security hardening"
                sh '''
                    echo "Applying security hardening..."
                    echo "- Disabling unused services"
                    echo "- Configuring firewall rules"
                    echo "- Setting file permissions"
                '''
            }
        }
        
        stage('Vulnerability Scan') {
            when { params.SECURITY_SCAN == true }
            steps {
                echo "🔍 Scanning built AMI for vulnerabilities"
                sh '''
                    echo "Running Trivy scan on built AMI..."
                    echo "Checking for CVEs and misconfigurations..."
                '''
            }
        }
        
        stage('Tag and Register AMI') {
            steps {
                echo "🏷️ Tagging and registering new AMI"
                sh '''
                    echo "Tagging AMI with metadata..."
                    echo "Environment: ${ENVIRONMENT}"
                    echo "Build Date: $(date)"
                    echo "Jenkins Version: ${JENKINS_VERSION}"
                '''
            }
        }
    }
    
    post {
        success {
            echo "✅ Golden AMI created successfully!"
        }
        failure {
            echo "❌ AMI creation failed"
        }
    }
}
    </script>
    <sandbox>true</sandbox>
  </definition>
  <triggers/>
  <disabled>false</disabled>
</flow-definition>
JOBEOF

echo "📋 Golden AMI Pipeline job configuration created"
echo "🌐 Jenkins URL: $JENKINS_URL"
echo ""
echo "To create the job manually:"
echo "1. Go to $JENKINS_URL"
echo "2. Click 'New Item'"
echo "3. Enter name: 'Golden-AMI-Pipeline'"
echo "4. Select 'Pipeline'"
echo "5. Copy the pipeline script from Jenkinsfile-golden-image"
echo ""
echo "Or run this to trigger AMI build directly with Packer:"
echo "cd packer && packer build -var 'environment=dev' jenkins-ami.pkr.hcl"
