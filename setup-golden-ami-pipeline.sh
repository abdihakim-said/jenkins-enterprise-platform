#!/bin/bash
# Setup Golden AMI Pipeline for End-to-End Testing

set -e

JENKINS_URL="http://dev-jenkins-alb-121130223.us-east-1.elb.amazonaws.com:8080"
JENKINS_USER="admin"
JENKINS_PASSWORD=$(aws ssm get-parameter --name "/jenkins/staging/admin-password" --with-decryption --query "Parameter.Value" --output text --region us-east-1)

echo "🚀 Setting up Golden AMI Pipeline..."

# Get Jenkins crumb for CSRF protection
CRUMB=$(curl -s "$JENKINS_URL/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,\":\",//crumb)" --user "$JENKINS_USER:$JENKINS_PASSWORD")

# Create Jenkins job
curl -X POST "$JENKINS_URL/createItem?name=Golden-AMI-Pipeline" \
  --user "$JENKINS_USER:$JENKINS_PASSWORD" \
  --header "$CRUMB" \
  --header "Content-Type: application/xml" \
  --data-binary @- << 'EOF'
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job">
  <description>End-to-End Golden AMI Pipeline with Testing</description>
  <properties>
    <hudson.model.ParametersDefinitionProperty>
      <parameterDefinitions>
        <hudson.model.ChoiceParameterDefinition>
          <name>ENVIRONMENT</name>
          <choices class="java.util.Arrays$ArrayList">
            <a class="string-array">
              <string>staging</string>
              <string>production</string>
              <string>dev</string>
            </a>
          </choices>
        </hudson.model.ChoiceParameterDefinition>
        <hudson.model.BooleanParameterDefinition>
          <name>SKIP_SECURITY_SCAN</name>
          <defaultValue>false</defaultValue>
        </hudson.model.BooleanParameterDefinition>
      </parameterDefinitions>
    </hudson.model.ParametersDefinitionProperty>
  </properties>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition">
    <script>
pipeline {
    agent any
    
    environment {
        AWS_DEFAULT_REGION = 'us-east-1'
        PACKER_LOG = '1'
    }
    
    stages {
        stage('🚀 Initialize') {
            steps {
                echo "Starting Golden AMI build for ${params.ENVIRONMENT}"
                sh 'aws sts get-caller-identity'
            }
        }
        
        stage('🔨 Build Golden AMI') {
            steps {
                script {
                    sh '''
                        cd packer
                        packer init jenkins-ami.pkr.hcl
                        packer validate jenkins-ami.pkr.hcl
                        packer build -var environment=${ENVIRONMENT} jenkins-ami.pkr.hcl | tee ../packer-build.log
                        
                        # Extract AMI ID
                        AMI_ID=$(grep 'artifact,0,id' ../packer-build.log | cut -d, -f6 | cut -d: -f2)
                        echo "Built AMI: ${AMI_ID}"
                        echo "${AMI_ID}" > ../ami-id.txt
                    '''
                }
            }
        }
        
        stage('🔒 Security Scan') {
            when { not { params.SKIP_SECURITY_SCAN } }
            steps {
                script {
                    sh '''
                        AMI_ID=$(cat ami-id.txt)
                        echo "Running security scan on AMI: ${AMI_ID}"
                        
                        # Launch test instance
                        INSTANCE_ID=$(aws ec2 run-instances \
                            --image-id ${AMI_ID} \
                            --instance-type t3.small \
                            --key-name dev-jenkins-enterprise-platform-key \
                            --security-group-ids $(terraform output -raw jenkins_security_group_id) \
                            --subnet-id $(terraform output -raw public_subnet_ids | cut -d',' -f1) \
                            --query 'Instances[0].InstanceId' --output text)
                        
                        echo "Launched test instance: ${INSTANCE_ID}"
                        
                        # Wait for running
                        aws ec2 wait instance-running --instance-ids ${INSTANCE_ID}
                        
                        # Get IP
                        INSTANCE_IP=$(aws ec2 describe-instances \
                            --instance-ids ${INSTANCE_ID} \
                            --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
                        
                        echo "Instance IP: ${INSTANCE_IP}"
                        
                        # Wait for SSH
                        timeout 300 bash -c 'until nc -z ${INSTANCE_IP} 22; do sleep 5; done'
                        
                        # Run Trivy scan
                        ssh -o StrictHostKeyChecking=no ubuntu@${INSTANCE_IP} '
                            trivy --version
                            trivy fs --format table --severity HIGH,CRITICAL /
                        '
                        
                        # Cleanup
                        aws ec2 terminate-instances --instance-ids ${INSTANCE_ID}
                    '''
                }
            }
        }
        
        stage('✅ End-to-End Testing') {
            steps {
                script {
                    sh '''
                        AMI_ID=$(cat ami-id.txt)
                        echo "Running E2E tests on AMI: ${AMI_ID}"
                        
                        # Launch test instance
                        INSTANCE_ID=$(aws ec2 run-instances \
                            --image-id ${AMI_ID} \
                            --instance-type t3.small \
                            --key-name dev-jenkins-enterprise-platform-key \
                            --security-group-ids $(terraform output -raw jenkins_security_group_id) \
                            --subnet-id $(terraform output -raw public_subnet_ids | cut -d',' -f1) \
                            --query 'Instances[0].InstanceId' --output text)
                        
                        # Wait and get IP
                        aws ec2 wait instance-running --instance-ids ${INSTANCE_ID}
                        INSTANCE_IP=$(aws ec2 describe-instances \
                            --instance-ids ${INSTANCE_ID} \
                            --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
                        
                        # Wait for SSH
                        timeout 300 bash -c 'until nc -z ${INSTANCE_IP} 22; do sleep 5; done'
                        sleep 60  # Wait for Jenkins to start
                        
                        # Run comprehensive tests
                        ssh -o StrictHostKeyChecking=no ubuntu@${INSTANCE_IP} '
                            echo "=== Testing All Tools ==="
                            java -version
                            sudo systemctl status jenkins --no-pager
                            docker --version
                            aws --version
                            terraform --version
                            packer --version
                            trivy --version
                            kubectl version --client
                            
                            echo "=== Testing Jenkins Web Interface ==="
                            timeout 300 bash -c "until curl -s http://localhost:8080/login; do sleep 10; done"
                            curl -s http://localhost:8080/login | grep -q "Jenkins" && echo "✅ Jenkins UI accessible"
                            
                            echo "=== Testing Docker ==="
                            sudo docker run hello-world
                            
                            echo "=== All tests passed! ==="
                        '
                        
                        # Cleanup
                        aws ec2 terminate-instances --instance-ids ${INSTANCE_ID}
                    '''
                }
            }
        }
        
        stage('🚀 Update Infrastructure') {
            steps {
                script {
                    sh '''
                        AMI_ID=$(cat ami-id.txt)
                        echo "Updating infrastructure with new AMI: ${AMI_ID}"
                        
                        # Update terraform.tfvars with new AMI
                        sed -i.bak "s/jenkins_ami_id = .*/jenkins_ami_id = \"${AMI_ID}\"/" terraform.tfvars
                        
                        # Plan and apply
                        terraform plan -out=ami-update.tfplan
                        terraform apply -auto-approve ami-update.tfplan
                        
                        echo "✅ Infrastructure updated with new Golden AMI"
                    '''
                }
            }
        }
    }
    
    post {
        always {
            archiveArtifacts artifacts: '**/*.log,**/*.txt', allowEmptyArchive: true
        }
        success {
            script {
                def amiId = readFile('ami-id.txt').trim()
                echo "🎉 Golden AMI Pipeline Success! New AMI: ${amiId}"
            }
        }
        failure {
            echo "❌ Golden AMI Pipeline Failed!"
        }
    }
}
    </script>
    <sandbox>true</sandbox>
  </definition>
</flow-definition>
EOF

echo "✅ Golden AMI Pipeline created successfully!"
echo "🌐 Access at: $JENKINS_URL/job/Golden-AMI-Pipeline/"
echo ""
echo "🎯 Pipeline includes:"
echo "- AMI building with Packer"
echo "- Security scanning with Trivy"
echo "- End-to-end testing"
echo "- Infrastructure updates"
