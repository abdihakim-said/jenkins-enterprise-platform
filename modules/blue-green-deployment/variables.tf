variable "kms_key_id" {
  description = "KMS key ID for encryption"
  type        = string
}

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where resources will be created"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs"
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group ID for Jenkins instances"
  type        = string
}

variable "iam_instance_profile" {
  description = "IAM instance profile name for Jenkins instances"
  type        = string
}

variable "target_group_arn" {
  description = "Target group ARN for load balancer"
  type        = string
}

variable "efs_file_system_id" {
  description = "EFS file system ID for Jenkins data"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for Jenkins"
  type        = string
  default     = "t3.medium"
}

variable "active_deployment" {
  description = "Active deployment color (blue or green)"
  type        = string
  default     = "blue"
  
  validation {
    condition     = contains(["blue", "green"], var.active_deployment)
    error_message = "Active deployment must be either 'blue' or 'green'."
  }
}

variable "blue_ami_id" {
  description = "AMI ID for blue deployment (optional, uses latest golden AMI if not specified)"
  type        = string
  default     = ""
}

variable "green_ami_id" {
  description = "AMI ID for green deployment (optional, uses latest golden AMI if not specified)"
  type        = string
  default     = ""
}

variable "min_size" {
  description = "Minimum number of instances in Auto Scaling Group"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of instances in Auto Scaling Group"
  type        = number
  default     = 3
}

variable "desired_capacity" {
  description = "Desired number of instances in Auto Scaling Group"
  type        = number
  default     = 1
}

variable "health_check_grace_period" {
  description = "Health check grace period in seconds"
  type        = number
  default     = 300
}

variable "root_volume_size" {
  description = "Size of root EBS volume in GB"
  type        = number
  default     = 50
}

variable "health_check_url" {
  description = "Health check URL for application validation"
  type        = string
  default     = "/login"
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
