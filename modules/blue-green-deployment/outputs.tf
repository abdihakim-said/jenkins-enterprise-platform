output "blue_asg_name" {
  description = "Name of the blue Auto Scaling Group"
  value       = aws_autoscaling_group.blue.name
}

output "green_asg_name" {
  description = "Name of the green Auto Scaling Group"
  value       = aws_autoscaling_group.green.name
}

output "blue_launch_template_id" {
  description = "ID of the blue launch template"
  value       = aws_launch_template.blue.id
}

output "green_launch_template_id" {
  description = "ID of the green launch template"
  value       = aws_launch_template.green.id
}

output "active_deployment" {
  description = "Currently active deployment color"
  value       = var.active_deployment
}

output "inactive_deployment" {
  description = "Currently inactive deployment color"
  value       = var.active_deployment == "blue" ? "green" : "blue"
}

output "deployment_orchestrator_function_name" {
  description = "Name of the Lambda deployment orchestrator function"
  value       = aws_lambda_function.deployment_orchestrator.function_name
}

output "deployment_notifications_topic_arn" {
  description = "ARN of the SNS topic for deployment notifications"
  value       = aws_sns_topic.deployment_notifications.arn
}

output "deployment_log_group_name" {
  description = "Name of the CloudWatch log group for deployment logs"
  value       = aws_cloudwatch_log_group.deployment_logs.name
}

output "blue_cpu_alarm_name" {
  description = "Name of the blue environment CPU alarm"
  value       = aws_cloudwatch_metric_alarm.blue_high_cpu.alarm_name
}

output "green_cpu_alarm_name" {
  description = "Name of the green environment CPU alarm"
  value       = aws_cloudwatch_metric_alarm.green_high_cpu.alarm_name
}
