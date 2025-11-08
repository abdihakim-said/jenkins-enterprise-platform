output "dashboard_url" {
  description = "URL to the enhanced CloudWatch dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.jenkins_observability.dashboard_name}"
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for enhanced alerts"
  value       = aws_sns_topic.alerts.arn
}

output "dashboard_name" {
  description = "Name of the enhanced CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.jenkins_observability.dashboard_name
}
