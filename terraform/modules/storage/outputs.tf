# Storage Module Outputs
# Jenkins Enterprise Platform - Storage Module
# Version: 2.0

# S3 Outputs
output "jenkins_backup_bucket_name" {
  description = "Name of the Jenkins backup S3 bucket"
  value       = aws_s3_bucket.jenkins_backup.bucket
}

output "jenkins_backup_bucket_arn" {
  description = "ARN of the Jenkins backup S3 bucket"
  value       = aws_s3_bucket.jenkins_backup.arn
}

output "jenkins_backup_bucket_domain_name" {
  description = "Domain name of the Jenkins backup S3 bucket"
  value       = aws_s3_bucket.jenkins_backup.bucket_domain_name
}

# EFS Outputs (conditional)
output "efs_id" {
  description = "EFS File System ID"
  value       = var.enable_efs ? aws_efs_file_system.jenkins_efs[0].id : null
}

output "efs_arn" {
  description = "EFS File System ARN"
  value       = var.enable_efs ? aws_efs_file_system.jenkins_efs[0].arn : null
}

output "efs_dns_name" {
  description = "EFS DNS name for mounting"
  value       = var.enable_efs ? aws_efs_file_system.jenkins_efs[0].dns_name : null
}

output "efs_mount_target_ids" {
  description = "List of EFS mount target IDs"
  value       = var.enable_efs ? aws_efs_mount_target.jenkins_efs_mount[*].id : []
}

output "efs_mount_target_dns_names" {
  description = "List of EFS mount target DNS names"
  value       = var.enable_efs ? aws_efs_mount_target.jenkins_efs_mount[*].dns_name : []
}

output "efs_security_group_id" {
  description = "Security group ID for EFS access"
  value       = var.enable_efs ? aws_security_group.efs_sg[0].id : null
}

output "jenkins_home_access_point_id" {
  description = "EFS Access Point ID for Jenkins home directory"
  value       = var.enable_efs ? aws_efs_access_point.jenkins_home[0].id : null
}

output "jenkins_home_access_point_arn" {
  description = "EFS Access Point ARN for Jenkins home directory"
  value       = var.enable_efs ? aws_efs_access_point.jenkins_home[0].arn : null
}

output "jenkins_builds_access_point_id" {
  description = "EFS Access Point ID for Jenkins builds directory"
  value       = var.enable_efs ? aws_efs_access_point.jenkins_builds[0].id : null
}

output "jenkins_builds_access_point_arn" {
  description = "EFS Access Point ARN for Jenkins builds directory"
  value       = var.enable_efs ? aws_efs_access_point.jenkins_builds[0].arn : null
}

# SSM Parameters
output "efs_ssm_parameter_id" {
  description = "SSM Parameter name containing EFS ID"
  value       = var.enable_efs ? aws_ssm_parameter.efs_id[0].name : null
}

output "efs_ssm_parameter_dns" {
  description = "SSM Parameter name containing EFS DNS name"
  value       = var.enable_efs ? aws_ssm_parameter.efs_dns_name[0].name : null
}

output "s3_backup_ssm_parameter" {
  description = "SSM Parameter name containing S3 backup bucket name"
  value       = aws_ssm_parameter.s3_backup_bucket.name
}

# CloudWatch
output "efs_cloudwatch_log_group_name" {
  description = "CloudWatch log group name for EFS performance monitoring"
  value       = var.enable_efs ? aws_cloudwatch_log_group.efs_performance[0].name : null
}

output "efs_cloudwatch_log_group_arn" {
  description = "CloudWatch log group ARN for EFS performance monitoring"
  value       = var.enable_efs ? aws_cloudwatch_log_group.efs_performance[0].arn : null
}

# Storage Summary
output "storage_summary" {
  description = "Summary of storage resources created"
  value = {
    s3_backup_bucket_created = true
    efs_enabled             = var.enable_efs
    efs_encrypted           = var.enable_efs ? var.efs_encryption_enabled : false
    efs_backup_enabled      = var.enable_efs ? var.efs_backup_enabled : false
    efs_performance_mode    = var.enable_efs ? var.efs_performance_mode : null
    efs_throughput_mode     = var.enable_efs ? var.efs_throughput_mode : null
    backup_retention_days   = var.backup_retention_days
  }
}
