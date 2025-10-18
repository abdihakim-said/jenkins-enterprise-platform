# S3 Backup Module Outputs
# Epic 3: Story 4.3 - S3 bucket outputs for Jenkins backup

output "bucket_name" {
  description = "Name of the S3 backup bucket"
  value       = aws_s3_bucket.jenkins_backup.id
}

output "bucket_arn" {
  description = "ARN of the S3 backup bucket"
  value       = aws_s3_bucket.jenkins_backup.arn
}

output "bucket_domain_name" {
  description = "Domain name of the S3 backup bucket"
  value       = aws_s3_bucket.jenkins_backup.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the S3 backup bucket"
  value       = aws_s3_bucket.jenkins_backup.bucket_regional_domain_name
}

output "bucket_hosted_zone_id" {
  description = "Hosted zone ID of the S3 backup bucket"
  value       = aws_s3_bucket.jenkins_backup.hosted_zone_id
}

output "bucket_region" {
  description = "Region of the S3 backup bucket"
  value       = aws_s3_bucket.jenkins_backup.region
}

# KMS Key Outputs
output "kms_key_id" {
  description = "ID of the KMS key used for S3 encryption"
  value       = aws_kms_key.s3_backup.key_id
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for S3 encryption"
  value       = aws_kms_key.s3_backup.arn
}

output "kms_key_alias" {
  description = "Alias of the KMS key used for S3 encryption"
  value       = aws_kms_alias.s3_backup.name
}

# Backup Configuration Outputs
output "backup_retention_days" {
  description = "Number of days backups are retained"
  value       = var.backup_retention_days
}

output "backup_schedule" {
  description = "Cron expression for backup schedule"
  value       = var.backup_schedule
}

output "lifecycle_configuration" {
  description = "S3 lifecycle configuration details"
  value = {
    transition_to_ia_days           = var.transition_to_ia_days
    transition_to_glacier_days      = var.transition_to_glacier_days
    transition_to_deep_archive_days = var.transition_to_deep_archive_days
    backup_retention_days           = var.backup_retention_days
    log_retention_days              = var.log_retention_days
  }
}

# Monitoring Outputs
output "backup_success_metric_name" {
  description = "CloudWatch metric name for backup success"
  value       = var.enable_backup_monitoring ? aws_cloudwatch_log_metric_filter.backup_success[0].name : null
}

output "backup_failure_metric_name" {
  description = "CloudWatch metric name for backup failures"
  value       = var.enable_backup_monitoring ? aws_cloudwatch_log_metric_filter.backup_failure[0].name : null
}

output "backup_failure_alarm_name" {
  description = "CloudWatch alarm name for backup failures"
  value       = var.enable_backup_monitoring ? aws_cloudwatch_metric_alarm.backup_failure[0].alarm_name : null
}

output "backup_missing_alarm_name" {
  description = "CloudWatch alarm name for missing backups"
  value       = var.enable_backup_monitoring ? aws_cloudwatch_metric_alarm.backup_missing[0].alarm_name : null
}

# Security Outputs
output "bucket_policy" {
  description = "S3 bucket policy JSON"
  value       = aws_s3_bucket_policy.jenkins_backup.policy
  sensitive   = true
}

output "encryption_configuration" {
  description = "S3 bucket encryption configuration"
  value = {
    kms_key_id    = aws_kms_key.s3_backup.arn
    sse_algorithm = "aws:kms"
  }
}

# Access Information
output "backup_access_commands" {
  description = "AWS CLI commands for backup operations"
  value = {
    list_backups = "aws s3 ls s3://${aws_s3_bucket.jenkins_backup.id}/"
    upload_backup = "aws s3 cp /path/to/backup.tar.gz s3://${aws_s3_bucket.jenkins_backup.id}/backups/"
    download_backup = "aws s3 cp s3://${aws_s3_bucket.jenkins_backup.id}/backups/backup.tar.gz /path/to/restore/"
    sync_directory = "aws s3 sync /var/lib/jenkins s3://${aws_s3_bucket.jenkins_backup.id}/jenkins-data/"
  }
}

# Cost Information
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown"
  value = {
    storage_standard = "~$0.023 per GB for first 50TB"
    storage_ia = "~$0.0125 per GB after ${var.transition_to_ia_days} days"
    storage_glacier = "~$0.004 per GB after ${var.transition_to_glacier_days} days"
    storage_deep_archive = "~$0.00099 per GB after ${var.transition_to_deep_archive_days} days"
    requests_put = "~$0.0005 per 1,000 PUT requests"
    requests_get = "~$0.0004 per 1,000 GET requests"
    kms_key = "~$1.00 per month for KMS key"
  }
}

# Backup Script Configuration
output "backup_script_config" {
  description = "Configuration for backup scripts"
  value = {
    bucket_name = aws_s3_bucket.jenkins_backup.id
    kms_key_id = aws_kms_key.s3_backup.key_id
    region = aws_s3_bucket.jenkins_backup.region
    retention_days = var.backup_retention_days
    compression_enabled = var.backup_compression
    encryption_enabled = var.backup_encryption
  }
}

# Disaster Recovery Information
output "disaster_recovery_info" {
  description = "Disaster recovery configuration"
  value = {
    point_in_time_recovery = var.enable_point_in_time_recovery
    rpo_hours = var.recovery_point_objective_hours
    rto_hours = var.recovery_time_objective_hours
    versioning_enabled = var.enable_versioning
    cross_region_replication = var.enable_cross_region_replication
  }
}

# Compliance Information
output "compliance_features" {
  description = "Compliance and governance features"
  value = {
    object_lock_enabled = var.enable_object_lock
    object_lock_mode = var.object_lock_mode
    object_lock_retention_days = var.object_lock_retention_days
    encryption_at_rest = true
    encryption_in_transit = true
    access_logging = var.enable_access_logging
    inventory_enabled = var.enable_inventory
  }
}

# Performance Configuration
output "performance_config" {
  description = "Performance optimization settings"
  value = {
    multipart_threshold = var.multipart_threshold
    multipart_chunksize = var.multipart_chunksize
    max_concurrent_requests = var.max_concurrent_requests
    intelligent_tiering = var.enable_intelligent_tiering
  }
}

# Backup Validation Commands
output "backup_validation_commands" {
  description = "Commands to validate backup integrity"
  value = {
    check_backup_size = "aws s3api head-object --bucket ${aws_s3_bucket.jenkins_backup.id} --key backups/latest.tar.gz --query ContentLength"
    verify_encryption = "aws s3api head-object --bucket ${aws_s3_bucket.jenkins_backup.id} --key backups/latest.tar.gz --query ServerSideEncryption"
    list_versions = "aws s3api list-object-versions --bucket ${aws_s3_bucket.jenkins_backup.id} --prefix backups/"
    check_lifecycle = "aws s3api get-bucket-lifecycle-configuration --bucket ${aws_s3_bucket.jenkins_backup.id}"
  }
}
