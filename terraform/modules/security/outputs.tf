# Security Module Outputs
# Jenkins Enterprise Platform - Security Module
# Version: 2.0

# Security Groups
output "jenkins_alb_security_group_id" {
  description = "ID of the Jenkins ALB security group"
  value       = aws_security_group.jenkins_alb.id
}

output "jenkins_instances_security_group_id" {
  description = "ID of the Jenkins instances security group"
  value       = aws_security_group.jenkins_instances.id
}

# IAM Resources
output "jenkins_instance_role_arn" {
  description = "ARN of the Jenkins instance IAM role"
  value       = aws_iam_role.jenkins_instance_role.arn
}

output "jenkins_instance_role_name" {
  description = "Name of the Jenkins instance IAM role"
  value       = aws_iam_role.jenkins_instance_role.name
}

output "jenkins_instance_profile_name" {
  description = "Name of the Jenkins instance profile"
  value       = aws_iam_instance_profile.jenkins_profile.name
}

output "jenkins_instance_profile_arn" {
  description = "ARN of the Jenkins instance profile"
  value       = aws_iam_instance_profile.jenkins_profile.arn
}

# Key Pair
output "jenkins_key_pair_name" {
  description = "Name of the Jenkins key pair"
  value       = aws_key_pair.jenkins_key.key_name
}

output "jenkins_key_pair_fingerprint" {
  description = "Fingerprint of the Jenkins key pair"
  value       = aws_key_pair.jenkins_key.fingerprint
}

# GuardDuty
output "guardduty_detector_id" {
  description = "ID of the GuardDuty detector"
  value       = var.enable_guardduty ? aws_guardduty_detector.main[0].id : null
}

output "guardduty_detector_arn" {
  description = "ARN of the GuardDuty detector"
  value       = var.enable_guardduty ? aws_guardduty_detector.main[0].arn : null
}

# Config
output "config_configuration_recorder_name" {
  description = "Name of the Config configuration recorder"
  value       = var.enable_config ? aws_config_configuration_recorder.main[0].name : null
}

output "config_bucket_name" {
  description = "Name of the Config S3 bucket"
  value       = var.enable_config ? aws_s3_bucket.config_bucket[0].bucket : null
}

output "config_bucket_arn" {
  description = "ARN of the Config S3 bucket"
  value       = var.enable_config ? aws_s3_bucket.config_bucket[0].arn : null
}

# CloudTrail
output "cloudtrail_arn" {
  description = "ARN of the CloudTrail"
  value       = var.enable_cloudtrail ? aws_cloudtrail.main[0].arn : null
}

output "cloudtrail_bucket_name" {
  description = "Name of the CloudTrail S3 bucket"
  value       = var.enable_cloudtrail ? aws_s3_bucket.cloudtrail_bucket[0].bucket : null
}

output "cloudtrail_bucket_arn" {
  description = "ARN of the CloudTrail S3 bucket"
  value       = var.enable_cloudtrail ? aws_s3_bucket.cloudtrail_bucket[0].arn : null
}

# VPC Flow Logs
output "vpc_flow_log_id" {
  description = "ID of the VPC Flow Log"
  value       = var.enable_vpc_flow_logs ? aws_flow_log.vpc_flow_log[0].id : null
}

output "vpc_flow_log_group_name" {
  description = "Name of the VPC Flow Log CloudWatch log group"
  value       = var.enable_vpc_flow_logs ? aws_cloudwatch_log_group.vpc_flow_log[0].name : null
}

output "vpc_flow_log_group_arn" {
  description = "ARN of the VPC Flow Log CloudWatch log group"
  value       = var.enable_vpc_flow_logs ? aws_cloudwatch_log_group.vpc_flow_log[0].arn : null
}

# Security Summary
output "security_summary" {
  description = "Summary of security resources created"
  value = {
    security_groups_created = 2
    iam_roles_created      = 1 + (var.enable_config ? 1 : 0) + (var.enable_vpc_flow_logs ? 1 : 0)
    guardduty_enabled      = var.enable_guardduty
    config_enabled         = var.enable_config
    cloudtrail_enabled     = var.enable_cloudtrail
    vpc_flow_logs_enabled  = var.enable_vpc_flow_logs
    key_pair_created       = true
  }
}
