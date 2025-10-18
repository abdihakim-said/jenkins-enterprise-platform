# Packer Variables for Jenkins Golden AMI
# Epic 2.2: Variables for Jenkins Master Golden AMI creation

# AWS Configuration
variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region where the AMI will be created"
}

variable "aws_profile" {
  type        = string
  default     = "default"
  description = "AWS profile to use for authentication"
}

# AMI Configuration
variable "ami_name_prefix" {
  type        = string
  default     = "jenkins-golden-ami"
  description = "Prefix for the AMI name"
}

variable "ami_description" {
  type        = string
  default     = "Jenkins Master Golden AMI with security hardening and monitoring"
  description = "Description for the AMI"
}

# Source AMI Configuration
variable "source_ami_filter" {
  type        = string
  default     = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
  description = "Filter to find the source AMI"
}

variable "source_ami_owners" {
  type        = list(string)
  default     = ["099720109477"]
  description = "List of AMI owners to consider (Canonical for Ubuntu)"
}

# Instance Configuration
variable "instance_type" {
  type        = string
  default     = "t3.large"
  description = "EC2 instance type for building the AMI"
  
  validation {
    condition = contains([
      "t3.small", "t3.medium", "t3.large", "t3.xlarge",
      "m5.large", "m5.xlarge", "m5.2xlarge",
      "c5.large", "c5.xlarge", "c5.2xlarge"
    ], var.instance_type)
    error_message = "Instance type must be a valid EC2 instance type suitable for Jenkins."
  }
}

# Network Configuration
variable "vpc_id" {
  type        = string
  default     = ""
  description = "VPC ID where the instance will be launched"
}

variable "subnet_id" {
  type        = string
  default     = ""
  description = "Subnet ID where the instance will be launched"
}

variable "security_group_id" {
  type        = string
  default     = ""
  description = "Security Group ID for the instance"
}

# Storage Configuration
variable "root_volume_size" {
  type        = number
  default     = 50
  description = "Size of the root volume in GB"
  
  validation {
    condition     = var.root_volume_size >= 20 && var.root_volume_size <= 1000
    error_message = "Root volume size must be between 20 and 1000 GB."
  }
}

variable "data_volume_size" {
  type        = number
  default     = 100
  description = "Size of the data volume in GB"
  
  validation {
    condition     = var.data_volume_size >= 50 && var.data_volume_size <= 2000
    error_message = "Data volume size must be between 50 and 2000 GB."
  }
}

variable "volume_type" {
  type        = string
  default     = "gp3"
  description = "EBS volume type"
  
  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2"], var.volume_type)
    error_message = "Volume type must be one of: gp2, gp3, io1, io2."
  }
}

variable "encrypt_volumes" {
  type        = bool
  default     = true
  description = "Whether to encrypt EBS volumes"
}

# Application Configuration
variable "jenkins_version" {
  type        = string
  default     = "2.426.1"
  description = "Jenkins version to install"
}

variable "java_version" {
  type        = string
  default     = "11"
  description = "Java version to install"
  
  validation {
    condition     = contains(["8", "11", "17"], var.java_version)
    error_message = "Java version must be 8, 11, or 17."
  }
}

variable "jenkins_port" {
  type        = number
  default     = 8080
  description = "Port for Jenkins web interface"
}

variable "jenkins_java_heap_max" {
  type        = string
  default     = "2g"
  description = "Maximum Java heap size for Jenkins"
}

variable "jenkins_java_heap_min" {
  type        = string
  default     = "512m"
  description = "Minimum Java heap size for Jenkins"
}

# Environment Configuration
variable "environment" {
  type        = string
  default     = "staging"
  description = "Environment name (dev, staging, production)"
  
  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be one of: dev, staging, production."
  }
}

variable "project_name" {
  type        = string
  default     = "jenkins-enterprise-platform"
  description = "Project name for tagging"
}

variable "team" {
  type        = string
  default     = "devops"
  description = "Team responsible for the AMI"
}

variable "cost_center" {
  type        = string
  default     = "engineering"
  description = "Cost center for billing"
}

# EFS Configuration
variable "efs_file_system_id" {
  type        = string
  default     = ""
  description = "EFS File System ID for shared storage"
}

variable "efs_mount_point" {
  type        = string
  default     = "/mnt/efs"
  description = "Mount point for EFS"
}

# Security Configuration
variable "enable_security_hardening" {
  type        = bool
  default     = true
  description = "Enable security hardening during AMI build"
}

variable "enable_monitoring" {
  type        = bool
  default     = true
  description = "Enable monitoring agents installation"
}

variable "enable_logging" {
  type        = bool
  default     = true
  description = "Enable centralized logging configuration"
}

# SSH Configuration
variable "ssh_username" {
  type        = string
  default     = "ubuntu"
  description = "SSH username for connecting to the instance"
}

variable "ssh_timeout" {
  type        = string
  default     = "20m"
  description = "SSH connection timeout"
}

# Build Configuration
variable "build_timeout" {
  type        = string
  default     = "60m"
  description = "Maximum time to wait for the build to complete"
}

variable "enable_t2_unlimited" {
  type        = bool
  default     = false
  description = "Enable T2/T3 unlimited mode"
}

# Tagging
variable "additional_tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags to apply to the AMI"
}

# Validation and Testing
variable "run_validation_tests" {
  type        = bool
  default     = true
  description = "Run validation tests after AMI creation"
}

variable "skip_create_ami" {
  type        = bool
  default     = false
  description = "Skip AMI creation (for testing)"
}

# Cleanup Configuration
variable "cleanup_temp_files" {
  type        = bool
  default     = true
  description = "Clean up temporary files after build"
}

variable "cleanup_logs" {
  type        = bool
  default     = true
  description = "Clean up build logs after AMI creation"
}
