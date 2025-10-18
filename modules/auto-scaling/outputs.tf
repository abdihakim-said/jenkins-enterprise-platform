output "asg_name" {
  description = "Auto Scaling Group name"
  value       = aws_autoscaling_group.jenkins.name
}

output "asg_arn" {
  description = "Auto Scaling Group ARN"
  value       = aws_autoscaling_group.jenkins.arn
}

output "launch_template_id" {
  description = "Launch template ID"
  value       = aws_launch_template.jenkins.id
}

output "launch_template_version" {
  description = "Launch template version"
  value       = aws_launch_template.jenkins.latest_version
}
