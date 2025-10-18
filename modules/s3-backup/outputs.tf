output "backup_bucket_name" {
  description = "S3 backup bucket name"
  value       = aws_s3_bucket.jenkins_backup.bucket
}

output "backup_bucket_arn" {
  description = "S3 backup bucket ARN"
  value       = aws_s3_bucket.jenkins_backup.arn
}

output "backup_bucket_domain_name" {
  description = "S3 backup bucket domain name"
  value       = aws_s3_bucket.jenkins_backup.bucket_domain_name
}

output "replica_bucket_name" {
  description = "S3 replica bucket name"
  value       = var.enable_cross_region_replication ? aws_s3_bucket.jenkins_backup_replica[0].bucket : null
}

output "replica_bucket_arn" {
  description = "S3 replica bucket ARN"
  value       = var.enable_cross_region_replication ? aws_s3_bucket.jenkins_backup_replica[0].arn : null
}
