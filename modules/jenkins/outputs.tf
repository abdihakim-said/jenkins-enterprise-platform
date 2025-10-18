# Jenkins Module - Outputs
# Author: Abdihakim Said

output "launch_template_id" {
  description = "ID of the launch template"
  value       = aws_launch_template.jenkins.id
}

output "launch_template_arn" {
  description = "ARN of the launch template"
  value       = aws_launch_template.jenkins.arn
}

output "auto_scaling_group_id" {
  description = "ID of the Auto Scaling Group"
  value       = aws_autoscaling_group.jenkins.id
}

output "auto_scaling_group_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.jenkins.name
}

output "auto_scaling_group_arn" {
  description = "ARN of the Auto Scaling Group"
  value       = aws_autoscaling_group.jenkins.arn
}

output "key_pair_name" {
  description = "Name of the key pair"
  value       = aws_key_pair.jenkins.key_name
}

output "scale_up_policy_arn" {
  description = "ARN of the scale up policy"
  value       = aws_autoscaling_policy.scale_up.arn
}

output "scale_down_policy_arn" {
  description = "ARN of the scale down policy"
  value       = aws_autoscaling_policy.scale_down.arn
}

output "high_cpu_alarm_arn" {
  description = "ARN of the high CPU alarm"
  value       = aws_cloudwatch_metric_alarm.high_cpu.arn
}

output "low_cpu_alarm_arn" {
  description = "ARN of the low CPU alarm"
  value       = aws_cloudwatch_metric_alarm.low_cpu.arn
}
