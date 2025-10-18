# EFS Module - Outputs
# Author: Abdihakim Said

output "file_system_id" {
  description = "ID of the EFS file system"
  value       = aws_efs_file_system.jenkins.id
}

output "file_system_arn" {
  description = "ARN of the EFS file system"
  value       = aws_efs_file_system.jenkins.arn
}

output "dns_name" {
  description = "DNS name of the EFS file system"
  value       = aws_efs_file_system.jenkins.dns_name
}

output "mount_target_ids" {
  description = "IDs of the EFS mount targets"
  value       = aws_efs_mount_target.jenkins[*].id
}

output "mount_target_dns_names" {
  description = "DNS names of the EFS mount targets"
  value       = aws_efs_mount_target.jenkins[*].dns_name
}

output "access_point_jenkins_home_id" {
  description = "ID of the Jenkins home access point"
  value       = aws_efs_access_point.jenkins_home.id
}

output "access_point_jenkins_workspace_id" {
  description = "ID of the Jenkins workspace access point"
  value       = aws_efs_access_point.jenkins_workspace.id
}

output "access_point_jenkins_home_arn" {
  description = "ARN of the Jenkins home access point"
  value       = aws_efs_access_point.jenkins_home.arn
}

output "access_point_jenkins_workspace_arn" {
  description = "ARN of the Jenkins workspace access point"
  value       = aws_efs_access_point.jenkins_workspace.arn
}
