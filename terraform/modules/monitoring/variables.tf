# Monitoring Module Variables
# Jenkins Enterprise Platform - Monitoring and Alerting Module
# Version: 2.0

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group to monitor"
  type        = string
}

variable "load_balancer_arn_suffix" {
  description = "ARN suffix of the load balancer"
  type        = string
}

variable "target_group_arn_suffix" {
  description = "ARN suffix of the target group"
  type        = string
}

variable "notification_email" {
  description = "Email address for notifications"
  type        = string
  default     = ""
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for notifications"
  type        = string
  default     = ""
  sensitive   = true
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
