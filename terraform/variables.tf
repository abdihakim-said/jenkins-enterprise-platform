# Jenkins Enterprise Platform - Terraform Variables
# Comprehensive variable definitions for all infrastructure components
# Version: 2.0
# Date: 2025-08-18

# General Configuration
variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (staging, production, dev)"
  type        = string
  validation {
    condition     = can(regex("^(staging|production|dev|test)$", var.environment))
    error_message = "Environment must be one of: staging, production, dev, test."
  }
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "jenkins-enterprise-platform"
}

# Network Configuration
variable "create_vpc" {
  description = "Whether to create a new VPC or use existing"
  type        = bool
  default     = false
}

variable "vpc_name" {
  description = "Name of existing VPC (if create_vpc is false)"
  type        = string
  default     = "default"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24"]
}

# EC2 Configuration
variable "instance_type" {
  description = "EC2 instance type for Jenkins"
  type        = string
  default     = "t3.medium"
  validation {
    condition = can(regex("^[tm][0-9][a-z]*\\.(nano|micro|small|medium|large|xlarge|[0-9]+xlarge)$", var.instance_type))
    error_message = "Instance type must be a valid EC2 instance type."
  }
}

variable "golden_ami_id" {
  description = "Golden AMI ID for Jenkins instances (leave empty to use latest Ubuntu)"
  type        = string
  default     = "ami-07e6a1629519d7c47"
}

variable "root_volume_size" {
  description = "Size of root EBS volume in GB"
  type        = number
  default     = 30
  validation {
    condition     = var.root_volume_size >= 20 && var.root_volume_size <= 1000
    error_message = "Root volume size must be between 20 and 1000 GB."
  }
}

variable "public_key" {
  description = "Public key for EC2 key pair"
  type        = string
  sensitive   = true
}

# Auto Scaling Configuration
variable "asg_min_size" {
  description = "Minimum number of instances in ASG"
  type        = number
  default     = 1
  validation {
    condition     = var.asg_min_size >= 1 && var.asg_min_size <= 10
    error_message = "ASG minimum size must be between 1 and 10."
  }
}

variable "asg_max_size" {
  description = "Maximum number of instances in ASG"
  type        = number
  default     = 3
  validation {
    condition     = var.asg_max_size >= 1 && var.asg_max_size <= 20
    error_message = "ASG maximum size must be between 1 and 20."
  }
}

variable "asg_desired_capacity" {
  description = "Desired number of instances in ASG"
  type        = number
  default     = 1
  validation {
    condition     = var.asg_desired_capacity >= 1 && var.asg_desired_capacity <= 20
    error_message = "ASG desired capacity must be between 1 and 20."
  }
}

# Application Configuration
variable "java_version" {
  description = "Java version to install"
  type        = string
  default     = "17"
  validation {
    condition     = can(regex("^(11|17|21)$", var.java_version))
    error_message = "Java version must be 11, 17, or 21."
  }
}

variable "jenkins_version" {
  description = "Jenkins version"
  type        = string
  default     = "2.516.1"
}

variable "jenkins_uid" {
  description = "UID for Jenkins user"
  type        = number
  default     = 1000
}

variable "jenkins_gid" {
  description = "GID for Jenkins group"
  type        = number
  default     = 1000
}

# EFS Configuration
variable "enable_efs" {
  description = "Enable EFS for persistent Jenkins storage"
  type        = bool
  default     = true
}

variable "efs_performance_mode" {
  description = "EFS performance mode"
  type        = string
  default     = "generalPurpose"
  validation {
    condition     = can(regex("^(generalPurpose|maxIO)$", var.efs_performance_mode))
    error_message = "EFS performance mode must be either 'generalPurpose' or 'maxIO'."
  }
}

variable "efs_throughput_mode" {
  description = "EFS throughput mode"
  type        = string
  default     = "bursting"
  validation {
    condition     = can(regex("^(bursting|provisioned)$", var.efs_throughput_mode))
    error_message = "EFS throughput mode must be either 'bursting' or 'provisioned'."
  }
}

variable "efs_provisioned_throughput" {
  description = "Provisioned throughput in MiB/s (only used when throughput_mode is provisioned)"
  type        = number
  default     = null
  validation {
    condition     = var.efs_provisioned_throughput == null || (var.efs_provisioned_throughput >= 1 && var.efs_provisioned_throughput <= 1024)
    error_message = "Provisioned throughput must be between 1 and 1024 MiB/s."
  }
}

variable "efs_encryption_enabled" {
  description = "Enable encryption at rest for EFS"
  type        = bool
  default     = true
}

variable "efs_backup_enabled" {
  description = "Enable automatic backups for EFS"
  type        = bool
  default     = true
}

# S3 Configuration
variable "backup_retention_days" {
  description = "Number of days to retain backups in S3"
  type        = number
  default     = 30
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 365
    error_message = "Backup retention days must be between 1 and 365."
  }
}

# Load Balancer Configuration
variable "enable_deletion_protection" {
  description = "Enable deletion protection for ALB"
  type        = bool
  default     = false
}

# Monitoring Configuration
variable "notification_email" {
  description = "Email address for monitoring notifications"
  type        = string
  default     = ""
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for notifications"
  type        = string
  default     = ""
  sensitive   = true
}

variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 30
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

# Security Configuration
variable "enable_guardduty" {
  description = "Enable AWS GuardDuty"
  type        = bool
  default     = true
}

variable "enable_config" {
  description = "Enable AWS Config"
  type        = bool
  default     = true
}

variable "enable_cloudtrail" {
  description = "Enable AWS CloudTrail"
  type        = bool
  default     = true
}

# Packer Configuration
variable "build_ami" {
  description = "Whether to build a new AMI with Packer"
  type        = bool
  default     = false
}

variable "packer_instance_type" {
  description = "Instance type for Packer build"
  type        = string
  default     = "t3.medium"
}

variable "source_ami_filter" {
  description = "Filter for source AMI (Ubuntu 22.04 LTS)"
  type        = string
  default     = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
}

variable "ssh_username" {
  description = "SSH username for Packer"
  type        = string
  default     = "ubuntu"
}

# Security Scanning Configuration
variable "enable_security_scan" {
  description = "Enable security scanning of the built AMI"
  type        = bool
  default     = true
}

variable "security_scan_tools" {
  description = "List of security scanning tools to use"
  type        = list(string)
  default     = ["trivy", "clamav", "lynis"]
}

variable "vulnerability_scan_severity" {
  description = "Minimum severity level for vulnerability scanning"
  type        = string
  default     = "HIGH"
  validation {
    condition     = can(regex("^(LOW|MEDIUM|HIGH|CRITICAL)$", var.vulnerability_scan_severity))
    error_message = "Vulnerability scan severity must be one of: LOW, MEDIUM, HIGH, CRITICAL."
  }
}

# Compliance Configuration
variable "compliance_framework" {
  description = "Compliance framework to follow (CIS, SOC2, etc.)"
  type        = string
  default     = "CIS"
  validation {
    condition     = can(regex("^(CIS|SOC2|PCI|HIPAA|NIST)$", var.compliance_framework))
    error_message = "Compliance framework must be one of: CIS, SOC2, PCI, HIPAA, NIST."
  }
}

variable "enable_vulnerability_scanning" {
  description = "Enable vulnerability scanning during build"
  type        = bool
  default     = true
}

# Cost Optimization
variable "enable_cost_optimization" {
  description = "Enable cost optimization features"
  type        = bool
  default     = true
}

variable "ami_cleanup_days" {
  description = "Number of days to keep old AMIs before cleanup"
  type        = number
  default     = 30
}

# Build Configuration
variable "build_timeout" {
  description = "Timeout for Packer build in minutes"
  type        = number
  default     = 60
}

variable "parallel_builds" {
  description = "Number of parallel builds to run"
  type        = number
  default     = 1
  validation {
    condition     = var.parallel_builds >= 1 && var.parallel_builds <= 5
    error_message = "Parallel builds must be between 1 and 5."
  }
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Feature Flags
variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring"
  type        = bool
  default     = true
}

variable "enable_backup_automation" {
  description = "Enable automated backup system"
  type        = bool
  default     = true
}

variable "enable_log_aggregation" {
  description = "Enable centralized log aggregation"
  type        = bool
  default     = true
}

variable "enable_performance_monitoring" {
  description = "Enable performance monitoring with Prometheus"
  type        = bool
  default     = true
}
