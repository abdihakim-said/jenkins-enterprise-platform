# Security Groups Module - Outputs
# Author: Abdihakim Said

output "alb_security_group_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb.id
}

output "jenkins_security_group_id" {
  description = "ID of the Jenkins security group"
  value       = aws_security_group.jenkins.id
}

output "efs_security_group_id" {
  description = "ID of the EFS security group"
  value       = aws_security_group.efs.id
}

output "rds_security_group_id" {
  description = "ID of the RDS security group"
  value       = aws_security_group.rds.id
}

output "security_group_ids" {
  description = "Map of all security group IDs"
  value = {
    alb     = aws_security_group.alb.id
    jenkins = aws_security_group.jenkins.id
    efs     = aws_security_group.efs.id
    rds     = aws_security_group.rds.id
  }
}
