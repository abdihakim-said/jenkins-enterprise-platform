# IAM Module - Outputs
# Author: Abdihakim Said

output "role_arn" {
  description = "ARN of the Jenkins IAM role"
  value       = aws_iam_role.jenkins.arn
}

output "role_name" {
  description = "Name of the Jenkins IAM role"
  value       = aws_iam_role.jenkins.name
}

output "instance_profile_name" {
  description = "Name of the Jenkins instance profile"
  value       = aws_iam_instance_profile.jenkins.name
}

output "instance_profile_arn" {
  description = "ARN of the Jenkins instance profile"
  value       = aws_iam_instance_profile.jenkins.arn
}

output "policy_arn" {
  description = "ARN of the Jenkins IAM policy"
  value       = aws_iam_policy.jenkins.arn
}

output "kms_key_id" {
  description = "ID of the KMS key"
  value       = aws_kms_key.jenkins.key_id
}

output "kms_key_arn" {
  description = "ARN of the KMS key"
  value       = aws_kms_key.jenkins.arn
}

output "kms_alias_name" {
  description = "Name of the KMS key alias"
  value       = aws_kms_alias.jenkins.name
}
