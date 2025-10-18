#!/bin/bash
# Enterprise Jenkins Golden AMI Setup Script - Fixed

set -e
set -x

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

echo "=== Enterprise Jenkins Golden AMI Setup Started ==="
echo "Timestamp: $(date)"

# System update
sudo apt update -y
sudo apt upgrade -y

# Install essential packages
sudo apt install -y \
    wget \
    curl \
    unzip \
    apt-transport-https \
    gnupg \
    lsb-release \
    fontconfig \
    nfs-common \
    mount \
    git \
    vim \
    htop \
    jq \
    python3 \
    python3-pip \
    build-essential \
    openjdk-17-jdk

# Set JAVA_HOME
echo 'export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64' | sudo tee -a /etc/environment
echo 'export PATH=$PATH:$JAVA_HOME/bin' | sudo tee -a /etc/environment

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install --bin-dir /usr/bin --install-dir /usr/bin/aws-cli --update
rm -f awscliv2.zip

# Install Terraform
curl -O https://releases.hashicorp.com/terraform/1.9.8/terraform_1.9.8_linux_amd64.zip
unzip terraform_1.9.8_linux_amd64.zip
sudo mv terraform /usr/local/bin/
rm -f terraform_1.9.8_linux_amd64.zip

# Install Packer
wget https://releases.hashicorp.com/packer/1.8.7/packer_1.8.7_linux_amd64.zip
unzip packer_1.8.7_linux_amd64.zip
sudo mv packer /usr/local/bin/
rm -f packer_1.8.7_linux_amd64.zip

# Install Trivy
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -
echo "deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee -a /etc/apt/sources.list.d/trivy.list
sudo apt update
sudo apt install -y trivy

# Install Docker
echo "=== Installing Docker ==="
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl enable docker
sudo usermod -aG docker ubuntu

# Install kubectl
echo "=== Installing kubectl ==="
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm -f kubectl

# Install Jenkins
echo "=== Installing Jenkins ==="
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | sudo tee /usr/share/keyrings/jenkins-keyring.asc > /dev/null
echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
sudo apt update
sudo apt install -y jenkins
sudo systemctl enable jenkins

# Cleanup
sudo apt autoremove -y
sudo apt autoclean

echo "=== Enterprise Jenkins Golden AMI Setup Completed Successfully ==="
echo "Timestamp: $(date)"
