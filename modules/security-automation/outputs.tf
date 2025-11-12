# Security Automation Module Outputs

output "guardduty_detector_id" {
  description = "ID of the GuardDuty detector"
  value       = aws_guardduty_detector.main.id
}

output "security_hub_arn" {
  description = "ARN of the Security Hub account"
  value       = aws_securityhub_account.main.arn
}

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail"
  value       = aws_cloudtrail.main.arn
}

output "cloudtrail_bucket_name" {
  description = "Name of the CloudTrail S3 bucket"
  value       = aws_s3_bucket.cloudtrail.bucket
}

output "security_alerts_topic_arn" {
  description = "ARN of the security alerts SNS topic"
  value       = aws_sns_topic.security_alerts.arn
}

output "security_responder_function_name" {
  description = "Name of the security responder Lambda function"
  value       = aws_lambda_function.security_responder.function_name
}
