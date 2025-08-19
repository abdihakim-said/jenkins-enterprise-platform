# Monitoring Module Outputs
# Jenkins Enterprise Platform - Monitoring and Alerting Module
# Version: 2.0

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = aws_sns_topic.jenkins_alerts.arn
}

output "cloudwatch_dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.jenkins_dashboard.dashboard_name}"
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.jenkins_logs.name
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.jenkins_logs.arn
}

output "alarm_names" {
  description = "Names of all CloudWatch alarms"
  value = [
    aws_cloudwatch_metric_alarm.jenkins_cpu_high.alarm_name,
    aws_cloudwatch_metric_alarm.jenkins_memory_high.alarm_name,
    aws_cloudwatch_metric_alarm.jenkins_disk_high.alarm_name,
    aws_cloudwatch_metric_alarm.jenkins_response_time_high.alarm_name,
    aws_cloudwatch_metric_alarm.jenkins_error_rate_high.alarm_name,
    aws_cloudwatch_metric_alarm.jenkins_instance_health.alarm_name
  ]
}

# Data sources
data "aws_region" "current" {}
