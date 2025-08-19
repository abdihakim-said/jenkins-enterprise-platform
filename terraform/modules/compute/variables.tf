# Compute Module Variables
# Jenkins Enterprise Platform - Compute Module
# Version: 2.0

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for compute resources"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for ALB"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for instances"
  type        = list(string)
}

# Security Groups
variable "alb_security_group_id" {
  description = "Security group ID for ALB"
  type        = string
}

variable "instances_security_group_id" {
  description = "Security group ID for Jenkins instances"
  type        = string
}

# IAM
variable "instance_profile_name" {
  description = "IAM instance profile name for Jenkins instances"
  type        = string
}

variable "key_pair_name" {
  description = "EC2 key pair name for Jenkins instances"
  type        = string
}

# Instance Configuration
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
  default     = ""
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

# Storage
variable "s3_backup_bucket" {
  description = "S3 bucket name for Jenkins backups"
  type        = string
}

variable "efs_id" {
  description = "EFS file system ID (empty if EFS not enabled)"
  type        = string
  default     = ""
}

# Load Balancer Configuration
variable "enable_deletion_protection" {
  description = "Enable deletion protection for ALB"
  type        = bool
  default     = false
}

variable "enable_https" {
  description = "Enable HTTPS listener on ALB"
  type        = bool
  default     = false
}

variable "ssl_certificate_arn" {
  description = "SSL certificate ARN for HTTPS listener"
  type        = string
  default     = ""
}

# Auto Scaling Configuration
variable "enable_auto_scaling" {
  description = "Enable auto scaling policies"
  type        = bool
  default     = true
}

variable "scale_up_threshold" {
  description = "CPU threshold for scaling up"
  type        = number
  default     = 80
  validation {
    condition     = var.scale_up_threshold >= 50 && var.scale_up_threshold <= 95
    error_message = "Scale up threshold must be between 50 and 95."
  }
}

variable "scale_down_threshold" {
  description = "CPU threshold for scaling down"
  type        = number
  default     = 20
  validation {
    condition     = var.scale_down_threshold >= 5 && var.scale_down_threshold <= 50
    error_message = "Scale down threshold must be between 5 and 50."
  }
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
