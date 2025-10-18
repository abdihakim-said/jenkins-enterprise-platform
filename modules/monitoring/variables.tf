variable "environment" {
  description = "Environment name"
  type        = string
}

variable "jenkins_asg_name" {
  description = "Jenkins Auto Scaling Group name"
  type        = string
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix"
  type        = string
}

variable "target_group_arn_suffix" {
  description = "Target group ARN suffix"
  type        = string
}

variable "sns_topic_name" {
  description = "SNS topic name for alerts"
  type        = string
}

variable "common_tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
