# Jenkins Golden AMI - Packer Configuration (Ubuntu 22.04)
# Epic 2.2: Hashicorp Packer to build Jenkins Master Golden AMI

packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.8"
      source  = "github.com/hashicorp/amazon"
    }
    ansible = {
      version = ">= 1.1.0"
      source = "github.com/hashicorp/ansible"
    }
  }
}

# Variables
variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region for AMI creation"
}

variable "instance_type" {
  type        = string
  default     = "t3.large"
  description = "EC2 instance type for building AMI (Ubuntu needs more resources)"
}

variable "source_ami_filter" {
  type        = string
  default     = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
  description = "Ubuntu 22.04 LTS AMI filter"
}

variable "ami_name_prefix" {
  type        = string
  default     = "jenkins-golden-ami-ubuntu"
  description = "AMI name prefix"
}

variable "environment" {
  type        = string
  default     = "staging"
  description = "Environment name"
}

variable "project_name" {
  type        = string
  default     = "jenkins-enterprise-platform"
  description = "Project name"
}



# Local variables
locals {
  timestamp = regex_replace(timestamp(), "[- TZ:]", "")
  ami_name  = "${var.ami_name_prefix}-${var.environment}-${local.timestamp}"
  
  common_tags = {
    Name         = local.ami_name
    Environment  = var.environment
    Project      = var.project_name
    CreatedBy    = "Packer"
    CreatedDate  = timestamp()
    OS           = "Ubuntu 22.04 LTS"
    Application  = "Jenkins Master"
    Version      = "2.426.1"
  }
}

# Data sources
data "amazon-ami" "ubuntu" {
  filters = {
    name                = var.source_ami_filter
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["099720109477"]  # Canonical
  region      = var.aws_region
}

# Build configuration
source "amazon-ebs" "jenkins_master" {
  # AWS Configuration
  region                      = var.aws_region
  source_ami                  = data.amazon-ami.ubuntu.id
  instance_type              = var.instance_type
  ssh_username               = "ubuntu"  # Ubuntu default user
  ssh_timeout                = "20m"
  
  associate_public_ip_address = true
  
  # AMI Configuration
  ami_name                   = local.ami_name
  ami_description            = "Jenkins Master Golden AMI (Ubuntu 22.04) - ${var.environment} - Built on ${timestamp()}"
  ami_virtualization_type    = "hvm"
  
  # EBS Configuration
  ebs_optimized             = true
  ena_support               = true
  sriov_support             = true
  
  # Root volume (Ubuntu)
  launch_block_device_mappings {
    device_name           = "/dev/sda1"  # Ubuntu uses /dev/sda1
    volume_type          = "gp3"
    volume_size          = 50
    iops                 = 3000
    throughput           = 125
    encrypted            = true
    delete_on_termination = true
  }
  
  # Additional volume for Jenkins data
  launch_block_device_mappings {
    device_name           = "/dev/sdf"
    volume_type          = "gp3"
    volume_size          = 100
    iops                 = 3000
    throughput           = 125
    encrypted            = true
    delete_on_termination = true
  }
  
  # Tags
  tags = local.common_tags
  
  # Snapshot tags
  snapshot_tags = merge(local.common_tags, {
    Name = "${local.ami_name}-snapshot"
  })
  
  # Run tags
  run_tags = merge(local.common_tags, {
    Name = "${local.ami_name}-builder"
  })
  
  # Temporary key pair
  temporary_key_pair_type = "ed25519"
  

}

# Build steps
build {
  name = "jenkins-golden-ami-ubuntu"
  sources = ["source.amazon-ebs.jenkins_master"]
  
  # Wait for cloud-init to complete
  provisioner "shell" {
    inline = [
      "echo 'Waiting for cloud-init to complete...'",
      "cloud-init status --wait",
      "echo 'Cloud-init completed successfully'"
    ]
  }
  
  # System updates and basic setup
  provisioner "shell" {
    script = "${path.root}/scripts/setup.sh"
  }
  
  # Enterprise Jenkins setup completed via shell script above
  # This approach is more reliable and follows industry best practices
  
  # Security hardening
  provisioner "shell" {
    script = "${path.root}/scripts/security-hardening.sh"
  }
  

  
  # Final cleanup and optimization
  provisioner "shell" {
    script = "${path.root}/scripts/cleanup.sh"
  }
  
  # Validate Jenkins installation
  provisioner "shell" {
    inline = [
      "echo 'Validating Jenkins installation...'",
      "sudo systemctl is-enabled jenkins",
      "java -version",
      "docker --version",
      "aws --version", 
      "terraform --version",
      "packer --version",
      "trivy --version",
      "kubectl version --client",
      "echo 'Validation completed successfully'"
    ]
  }
  
  # Create AMI manifest
  post-processor "manifest" {
    output = "manifest.json"
    strip_path = true
    custom_data = {
      ami_name           = local.ami_name
      source_ami         = data.amazon-ami.ubuntu.id
      instance_type      = var.instance_type
      region            = var.aws_region
      environment       = var.environment
      jenkins_version   = "2.426.1"
      java_version      = "17"
      os_version        = "Ubuntu 22.04 LTS"
      build_time        = timestamp()
    }
  }
}
