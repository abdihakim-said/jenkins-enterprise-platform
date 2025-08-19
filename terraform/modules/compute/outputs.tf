# Compute Module Outputs
# Jenkins Enterprise Platform - Compute Module
# Version: 2.0

# Load Balancer Outputs
output "jenkins_alb_arn" {
  description = "ARN of the Jenkins Application Load Balancer"
  value       = aws_lb.jenkins_alb.arn
}

output "jenkins_alb_dns_name" {
  description = "DNS name of the Jenkins Application Load Balancer"
  value       = aws_lb.jenkins_alb.dns_name
}

output "jenkins_alb_zone_id" {
  description = "Zone ID of the Jenkins Application Load Balancer"
  value       = aws_lb.jenkins_alb.zone_id
}

output "jenkins_alb_url" {
  description = "URL of the Jenkins Application Load Balancer"
  value       = "http://${aws_lb.jenkins_alb.dns_name}"
}

output "jenkins_alb_arn_suffix" {
  description = "ARN suffix of the Jenkins Application Load Balancer"
  value       = aws_lb.jenkins_alb.arn_suffix
}

# Target Group Outputs
output "jenkins_target_group_arn" {
  description = "ARN of the Jenkins target group"
  value       = aws_lb_target_group.jenkins_tg.arn
}

output "jenkins_target_group_name" {
  description = "Name of the Jenkins target group"
  value       = aws_lb_target_group.jenkins_tg.name
}

output "jenkins_target_group_arn_suffix" {
  description = "ARN suffix of the Jenkins target group"
  value       = aws_lb_target_group.jenkins_tg.arn_suffix
}

# Launch Template Outputs
output "jenkins_launch_template_id" {
  description = "ID of the Jenkins launch template"
  value       = aws_launch_template.jenkins_lt.id
}

output "jenkins_launch_template_name" {
  description = "Name of the Jenkins launch template"
  value       = aws_launch_template.jenkins_lt.name
}

output "jenkins_launch_template_latest_version" {
  description = "Latest version of the Jenkins launch template"
  value       = aws_launch_template.jenkins_lt.latest_version
}

output "jenkins_launch_template_arn" {
  description = "ARN of the Jenkins launch template"
  value       = aws_launch_template.jenkins_lt.arn
}

# Auto Scaling Group Outputs
output "jenkins_autoscaling_group_name" {
  description = "Name of the Jenkins Auto Scaling Group"
  value       = aws_autoscaling_group.jenkins_asg.name
}

output "jenkins_autoscaling_group_arn" {
  description = "ARN of the Jenkins Auto Scaling Group"
  value       = aws_autoscaling_group.jenkins_asg.arn
}

output "jenkins_autoscaling_group_min_size" {
  description = "Minimum size of the Jenkins Auto Scaling Group"
  value       = aws_autoscaling_group.jenkins_asg.min_size
}

output "jenkins_autoscaling_group_max_size" {
  description = "Maximum size of the Jenkins Auto Scaling Group"
  value       = aws_autoscaling_group.jenkins_asg.max_size
}

output "jenkins_autoscaling_group_desired_capacity" {
  description = "Desired capacity of the Jenkins Auto Scaling Group"
  value       = aws_autoscaling_group.jenkins_asg.desired_capacity
}

# Auto Scaling Policies
output "jenkins_scale_up_policy_arn" {
  description = "ARN of the Jenkins scale up policy"
  value       = aws_autoscaling_policy.jenkins_scale_up.arn
}

output "jenkins_scale_down_policy_arn" {
  description = "ARN of the Jenkins scale down policy"
  value       = aws_autoscaling_policy.jenkins_scale_down.arn
}

# CloudWatch Alarms
output "jenkins_cpu_high_alarm_name" {
  description = "Name of the Jenkins CPU high alarm"
  value       = aws_cloudwatch_metric_alarm.jenkins_cpu_high.alarm_name
}

output "jenkins_cpu_low_alarm_name" {
  description = "Name of the Jenkins CPU low alarm"
  value       = aws_cloudwatch_metric_alarm.jenkins_cpu_low.alarm_name
}

# AMI Information
output "golden_ami_id" {
  description = "ID of the Golden AMI used for Jenkins instances"
  value       = var.golden_ami_id != "" ? var.golden_ami_id : data.aws_ami.ubuntu.id
}

output "ubuntu_ami_id" {
  description = "ID of the latest Ubuntu AMI (fallback)"
  value       = data.aws_ami.ubuntu.id
}

# Compute Summary
output "compute_summary" {
  description = "Summary of compute resources created"
  value = {
    load_balancer_created     = true
    target_group_created      = true
    launch_template_created   = true
    autoscaling_group_created = true
    auto_scaling_enabled      = var.enable_auto_scaling
    instance_type            = var.instance_type
    min_instances            = var.asg_min_size
    max_instances            = var.asg_max_size
    desired_instances        = var.asg_desired_capacity
    golden_ami_used          = var.golden_ami_id != ""
    java_version             = var.java_version
    jenkins_version          = var.jenkins_version
  }
}
