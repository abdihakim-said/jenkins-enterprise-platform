# Jenkins Enterprise Platform - Outputs
# Author: Abdihakim Said

# VPC Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.vpc.private_subnet_ids
}

# Load Balancer Outputs
output "jenkins_url" {
  description = "Jenkins application URL"
  value       = "http://${module.alb.dns_name}:8080"
}

output "load_balancer_dns_name" {
  description = "DNS name of the load balancer"
  value       = module.alb.dns_name
}

output "load_balancer_zone_id" {
  description = "Zone ID of the load balancer"
  value       = module.alb.zone_id
}

# Jenkins Outputs
output "jenkins_auto_scaling_group_name" {
  description = "Name of the Jenkins Auto Scaling Group"
  value       = module.jenkins.auto_scaling_group_name
}

output "jenkins_launch_template_id" {
  description = "ID of the Jenkins launch template"
  value       = module.jenkins.launch_template_id
}

# EFS Outputs
output "efs_file_system_id" {
  description = "ID of the EFS file system"
  value       = module.efs.file_system_id
}

output "efs_dns_name" {
  description = "DNS name of the EFS file system"
  value       = module.efs.dns_name
}

# Security Groups
output "jenkins_security_group_id" {
  description = "ID of the Jenkins security group"
  value       = module.security_groups.jenkins_security_group_id
}

output "alb_security_group_id" {
  description = "ID of the ALB security group"
  value       = module.security_groups.alb_security_group_id
}

output "efs_security_group_id" {
  description = "ID of the EFS security group"
  value       = module.security_groups.efs_security_group_id
}

# IAM Outputs
output "jenkins_role_arn" {
  description = "ARN of the Jenkins IAM role"
  value       = module.iam.role_arn
}

output "jenkins_instance_profile_name" {
  description = "Name of the Jenkins instance profile"
  value       = module.iam.instance_profile_name
}

# CloudWatch Outputs
output "jenkins_log_group_name" {
  description = "Name of the Jenkins CloudWatch log group"
  value       = module.cloudwatch.jenkins_log_group_name
}

# SSM Parameter for Jenkins Admin Password
output "jenkins_admin_password_parameter" {
  description = "SSM parameter name for Jenkins admin password"
  value       = "/jenkins/${var.environment}/admin-password"
  sensitive   = true
}

# Connection Information
output "connection_info" {
  description = "Connection information for Jenkins"
  value = {
    url                    = "http://${module.alb.dns_name}:8080"
    admin_username         = var.jenkins_admin_username
    admin_password_command = "aws ssm get-parameter --name '/jenkins/${var.environment}/admin-password' --with-decryption --query 'Parameter.Value' --output text --region ${var.aws_region}"
  }
}

# Inspector Outputs
output "inspector_sns_topic_arn" {
  description = "ARN of the Inspector notifications SNS topic"
  value       = module.inspector.sns_topic_arn
}

output "inspector_lambda_function_arn" {
  description = "ARN of the Inspector processor Lambda function"
  value       = module.inspector.lambda_function_arn
}

# VPC Endpoint Outputs
output "vpc_endpoint_s3_id" {
  description = "ID of the S3 VPC Endpoint"
  value       = module.vpc.vpc_endpoint_s3_id
}

output "vpc_endpoint_ec2_id" {
  description = "ID of the EC2 VPC Endpoint"
  value       = module.vpc.vpc_endpoint_ec2_id
}

output "vpc_endpoint_ssm_id" {
  description = "ID of the SSM VPC Endpoint"
  value       = module.vpc.vpc_endpoint_ssm_id
}

# Resource Summary
output "resource_summary" {
  description = "Summary of created resources"
  value = {
    vpc_id                    = module.vpc.vpc_id
    jenkins_url               = "http://${module.alb.dns_name}:8080"
    auto_scaling_group        = module.jenkins.auto_scaling_group_name
    efs_file_system           = module.efs.file_system_id
    instance_type             = var.jenkins_instance_type
    health_check_grace_period = var.health_check_grace_period
    inspector_enabled         = true
    vpc_endpoints_enabled     = true
  }
}
