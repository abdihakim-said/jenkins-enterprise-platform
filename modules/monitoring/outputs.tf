output "sns_topic_arn" {
  description = "SNS topic ARN"
  value       = aws_sns_topic.jenkins_alerts.arn
}

output "sns_topic_name" {
  description = "SNS topic name"
  value       = aws_sns_topic.jenkins_alerts.name
}
