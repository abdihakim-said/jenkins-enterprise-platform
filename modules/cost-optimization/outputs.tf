output "cost_reports_bucket" {
  description = "S3 bucket for cost reports"
  value       = aws_s3_bucket.cost_reports.bucket
}

output "cost_optimizer_lambda_arn" {
  description = "Cost optimizer Lambda function ARN"
  value       = aws_lambda_function.cost_optimizer.arn
}

output "cost_alerts_topic_arn" {
  description = "SNS topic ARN for cost alerts"
  value       = aws_sns_topic.cost_alerts.arn
}

output "cost_dashboard_url" {
  description = "CloudWatch dashboard URL for cost monitoring"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.cost_optimization.dashboard_name}"
}
