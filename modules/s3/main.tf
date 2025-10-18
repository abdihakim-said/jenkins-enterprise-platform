# S3 Backup Module for Jenkins Enterprise Platform
# Epic 3: Story 4.3 - Develop Terraform module for S3 bucket

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Local variables
locals {
  bucket_name = "${var.project_name}-${var.environment}-backup-${random_id.bucket_suffix.hex}"
  
  common_tags = merge(var.common_tags, {
    Module      = "s3-backup"
    Purpose     = "Jenkins backup storage"
    Environment = var.environment
    Project     = var.project_name
  })
}

# Random suffix for bucket name uniqueness
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# KMS key for S3 encryption
resource "aws_kms_key" "s3_backup" {
  description             = "KMS key for Jenkins backup S3 bucket encryption"
  deletion_window_in_days = var.kms_deletion_window
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow Jenkins instances to use the key"
        Effect = "Allow"
        Principal = {
          AWS = var.jenkins_role_arn
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-s3-backup-key"
  })
}

# KMS key alias
resource "aws_kms_alias" "s3_backup" {
  name          = "alias/${var.project_name}-${var.environment}-s3-backup"
  target_key_id = aws_kms_key.s3_backup.key_id
}

# S3 bucket for Jenkins backups
resource "aws_s3_bucket" "jenkins_backup" {
  bucket        = local.bucket_name
  force_destroy = var.force_destroy_bucket

  tags = merge(local.common_tags, {
    Name = local.bucket_name
  })
}

# S3 bucket versioning
resource "aws_s3_bucket_versioning" "jenkins_backup" {
  bucket = aws_s3_bucket.jenkins_backup.id
  
  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

# S3 bucket server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "jenkins_backup" {
  bucket = aws_s3_bucket.jenkins_backup.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3_backup.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

# S3 bucket public access block
resource "aws_s3_bucket_public_access_block" "jenkins_backup" {
  bucket = aws_s3_bucket.jenkins_backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 bucket lifecycle configuration
resource "aws_s3_bucket_lifecycle_configuration" "jenkins_backup" {
  bucket = aws_s3_bucket.jenkins_backup.id

  rule {
    id     = "jenkins_backup_lifecycle"
    status = "Enabled"

    # Transition to IA after 30 days
    transition {
      days          = var.transition_to_ia_days
      storage_class = "STANDARD_IA"
    }

    # Transition to Glacier after 90 days
    transition {
      days          = var.transition_to_glacier_days
      storage_class = "GLACIER"
    }

    # Transition to Deep Archive after 365 days
    transition {
      days          = var.transition_to_deep_archive_days
      storage_class = "DEEP_ARCHIVE"
    }

    # Delete old versions after retention period
    noncurrent_version_expiration {
      noncurrent_days = var.backup_retention_days
    }

    # Delete incomplete multipart uploads after 7 days
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Separate rule for log files
  rule {
    id     = "jenkins_logs_lifecycle"
    status = "Enabled"

    filter {
      prefix = "logs/"
    }

    expiration {
      days = var.log_retention_days
    }
  }

  # Rule for temporary files
  rule {
    id     = "temp_files_cleanup"
    status = "Enabled"

    filter {
      prefix = "temp/"
    }

    expiration {
      days = 7
    }
  }
}

# S3 bucket notification for backup monitoring
resource "aws_s3_bucket_notification" "jenkins_backup" {
  count  = var.enable_backup_notifications ? 1 : 0
  bucket = aws_s3_bucket.jenkins_backup.id

  topic {
    topic_arn = var.sns_topic_arn
    events    = ["s3:ObjectCreated:*", "s3:ObjectRemoved:*"]
  }

  depends_on = [aws_s3_bucket.jenkins_backup]
}

# S3 bucket policy for Jenkins access
resource "aws_s3_bucket_policy" "jenkins_backup" {
  bucket = aws_s3_bucket.jenkins_backup.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyInsecureConnections"
        Effect = "Deny"
        Principal = "*"
        Action = "s3:*"
        Resource = [
          aws_s3_bucket.jenkins_backup.arn,
          "${aws_s3_bucket.jenkins_backup.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
      {
        Sid    = "AllowJenkinsAccess"
        Effect = "Allow"
        Principal = {
          AWS = var.jenkins_role_arn
        }
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:GetBucketVersioning",
          "s3:ListBucketVersions",
          "s3:GetObjectVersion",
          "s3:DeleteObjectVersion"
        ]
        Resource = [
          aws_s3_bucket.jenkins_backup.arn,
          "${aws_s3_bucket.jenkins_backup.arn}/*"
        ]
      }
    ]
  })
}

# CloudWatch metric filter for backup monitoring
resource "aws_cloudwatch_log_metric_filter" "backup_success" {
  count          = var.enable_backup_monitoring ? 1 : 0
  name           = "${var.project_name}-${var.environment}-backup-success"
  log_group_name = var.jenkins_log_group_name
  pattern        = "[timestamp, request_id, level=\"INFO\", message=\"Backup completed successfully\"]"

  metric_transformation {
    name      = "JenkinsBackupSuccess"
    namespace = "Jenkins/Backup"
    value     = "1"
  }
}

# CloudWatch metric filter for backup failures
resource "aws_cloudwatch_log_metric_filter" "backup_failure" {
  count          = var.enable_backup_monitoring ? 1 : 0
  name           = "${var.project_name}-${var.environment}-backup-failure"
  log_group_name = var.jenkins_log_group_name
  pattern        = "[timestamp, request_id, level=\"ERROR\", message=\"Backup failed\"]"

  metric_transformation {
    name      = "JenkinsBackupFailure"
    namespace = "Jenkins/Backup"
    value     = "1"
  }
}

# CloudWatch alarm for backup failures
resource "aws_cloudwatch_metric_alarm" "backup_failure" {
  count               = var.enable_backup_monitoring ? 1 : 0
  alarm_name          = "${var.project_name}-${var.environment}-backup-failure"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "JenkinsBackupFailure"
  namespace           = "Jenkins/Backup"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors Jenkins backup failures"
  alarm_actions       = var.alarm_actions

  tags = local.common_tags
}

# CloudWatch alarm for missing backups
resource "aws_cloudwatch_metric_alarm" "backup_missing" {
  count               = var.enable_backup_monitoring ? 1 : 0
  alarm_name          = "${var.project_name}-${var.environment}-backup-missing"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "JenkinsBackupSuccess"
  namespace           = "Jenkins/Backup"
  period              = "86400"  # 24 hours
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "This metric monitors for missing daily backups"
  alarm_actions       = var.alarm_actions
  treat_missing_data  = "breaching"

  tags = local.common_tags
}

# S3 bucket for backup inventory
resource "aws_s3_bucket_inventory" "jenkins_backup" {
  count  = var.enable_inventory ? 1 : 0
  bucket = aws_s3_bucket.jenkins_backup.id
  name   = "jenkins-backup-inventory"

  included_object_versions = "All"

  schedule {
    frequency = "Daily"
  }

  destination {
    bucket {
      format     = "CSV"
      bucket_arn = aws_s3_bucket.jenkins_backup.arn
      prefix     = "inventory/"
      encryption {
        sse_kms {
          key_id = aws_kms_key.s3_backup.arn
        }
      }
    }
  }

  optional_fields = [
    "Size",
    "LastModifiedDate",
    "StorageClass",
    "ETag",
    "IsMultipartUploaded",
    "ReplicationStatus",
    "EncryptionStatus"
  ]
}
