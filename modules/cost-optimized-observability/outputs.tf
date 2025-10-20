output "dashboard_url" {
  description = "URL to the CloudWatch dashboard"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.jenkins_observability.dashboard_name}"
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = aws_sns_topic.alerts.arn
}

output "log_group_names" {
  description = "Names of the CloudWatch log groups"
  value = {
    application = aws_cloudwatch_log_group.jenkins_app.name
    system      = aws_cloudwatch_log_group.jenkins_system.name
  }
}

output "s3_logs_bucket" {
  description = "Name of the S3 bucket for log storage"
  value       = aws_s3_bucket.logs.bucket
}

output "monthly_cost_estimate" {
  description = "Estimated monthly cost in USD"
  value       = "~$15/month (CloudWatch metrics + S3 storage + minimal data transfer)"
}
