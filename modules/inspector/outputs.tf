output "sns_topic_arn" {
  description = "ARN of the Inspector notifications SNS topic"
  value       = aws_sns_topic.inspector_notifications.arn
}

output "lambda_function_arn" {
  description = "ARN of the Inspector processor Lambda function"
  value       = aws_lambda_function.inspector_processor.arn
}

output "cloudwatch_event_rule_arn" {
  description = "ARN of the Inspector findings CloudWatch event rule"
  value       = aws_cloudwatch_event_rule.inspector_findings.arn
}
