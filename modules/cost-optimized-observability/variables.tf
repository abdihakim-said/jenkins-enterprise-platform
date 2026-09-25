variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "alert_email" {
  description = "Email address for monitoring alerts"
  type        = string
  default     = ""
}

variable "efs_file_system_id" {
  description = "ID of the Jenkins EFS file system to monitor"
  type        = string
}

variable "alb_name" {
  description = "Name of the Jenkins Application Load Balancer to monitor"
  type        = string
}
