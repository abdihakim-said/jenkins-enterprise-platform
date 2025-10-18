# CloudWatch Module - Outputs
# Author: Abdihakim Said

output "jenkins_log_group_name" {
  description = "Name of the Jenkins application log group"
  value       = aws_cloudwatch_log_group.jenkins_application.name
}

output "jenkins_log_group_arn" {
  description = "ARN of the Jenkins application log group"
  value       = aws_cloudwatch_log_group.jenkins_application.arn
}

output "user_data_log_group_name" {
  description = "Name of the user data log group"
  value       = aws_cloudwatch_log_group.jenkins_user_data.name
}

output "system_log_group_name" {
  description = "Name of the system log group"
  value       = aws_cloudwatch_log_group.jenkins_system.name
}

output "dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.jenkins.dashboard_name}"
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = aws_sns_topic.jenkins_alerts.arn
}

output "high_error_rate_alarm_arn" {
  description = "ARN of the high error rate alarm"
  value       = aws_cloudwatch_metric_alarm.jenkins_high_error_rate.arn
}

output "high_response_time_alarm_arn" {
  description = "ARN of the high response time alarm"
  value       = aws_cloudwatch_metric_alarm.jenkins_high_response_time.arn
}
