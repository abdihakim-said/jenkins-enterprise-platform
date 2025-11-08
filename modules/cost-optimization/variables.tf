variable "environment" {
  description = "Environment name"
  type        = string
}

variable "jenkins_asg_name" {
  description = "Jenkins Auto Scaling Group name"
  type        = string
}

variable "jenkins_url" {
  description = "Jenkins URL for metrics collection"
  type        = string
}

variable "cost_alert_email" {
  description = "Email for cost alerts"
  type        = string
}

variable "monthly_budget_limit" {
  description = "Monthly budget limit in USD"
  type        = string
  default     = "200"
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
