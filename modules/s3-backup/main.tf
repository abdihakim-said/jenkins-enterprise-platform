#---------------------------------------------#
# Jenkins Enterprise Platform - S3 Backup Module
# Author: Abdihakim Said
# Epic 3, Story 4.3: Develop Terraform module for S3 bucket
# Epic 3, Story 4.2: Setup Purge policy for jobs, S3 backup
#---------------------------------------------#

# S3 Bucket for Jenkins backups
resource "aws_s3_bucket" "jenkins_backup" {
  bucket = "${var.environment}-jenkins-backup-${random_string.bucket_suffix.result}"

  tags = merge(var.common_tags, {
    Name = "${var.environment}-jenkins-backup"
    Purpose = "Jenkins Backup Storage"
    Epic = "Epic-3-Housekeeping"
    Story = "Story-4.3-S3-Module"
  })
}

resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

# Bucket versioning for backup integrity
resource "aws_s3_bucket_versioning" "jenkins_backup_versioning" {
  bucket = aws_s3_bucket.jenkins_backup.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "jenkins_backup_encryption" {
  bucket = aws_s3_bucket.jenkins_backup.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = var.kms_key_id
      sse_algorithm     = var.kms_key_id != null ? "aws:kms" : "AES256"
    }
    bucket_key_enabled = true
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "jenkins_backup_pab" {
  bucket = aws_s3_bucket.jenkins_backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle configuration for cost optimization (Epic 3, Story 4.2)
resource "aws_s3_bucket_lifecycle_configuration" "jenkins_backup_lifecycle" {
  bucket = aws_s3_bucket.jenkins_backup.id

  rule {
    id     = "jenkins_backup_lifecycle"
    status = "Enabled"

    # Transition to IA after 30 days
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    # Transition to Glacier after 90 days
    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    # Transition to Deep Archive after 365 days
    transition {
      days          = 365
      storage_class = "DEEP_ARCHIVE"
    }

    # Delete old versions after 2 years
    noncurrent_version_expiration {
      noncurrent_days = 730
    }

    # Delete incomplete multipart uploads after 7 days
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Purge policy for old job artifacts (Epic 3, Story 4.2)
  rule {
    id     = "jenkins_job_artifacts_purge"
    status = "Enabled"

    filter {
      prefix = "job-artifacts/"
    }

    expiration {
      days = var.job_artifacts_retention_days
    }
  }

  # Purge policy for build logs
  rule {
    id     = "jenkins_build_logs_purge"
    status = "Enabled"

    filter {
      prefix = "build-logs/"
    }

    expiration {
      days = var.build_logs_retention_days
    }
  }
}

# Cross-region replication for disaster recovery
resource "aws_s3_bucket" "jenkins_backup_replica" {
  count    = var.enable_cross_region_replication ? 1 : 0
  provider = aws.replica
  bucket   = "${var.environment}-jenkins-backup-replica-${random_string.bucket_suffix.result}"

  tags = merge(var.common_tags, {
    Name = "${var.environment}-jenkins-backup-replica"
    Purpose = "Jenkins Backup Replica"
    Type = "Disaster Recovery"
  })
}

resource "aws_s3_bucket_versioning" "jenkins_backup_replica_versioning" {
  count    = var.enable_cross_region_replication ? 1 : 0
  provider = aws.replica
  bucket   = aws_s3_bucket.jenkins_backup_replica[0].id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# Replication configuration
resource "aws_s3_bucket_replication_configuration" "jenkins_backup_replication" {
  count  = var.enable_cross_region_replication ? 1 : 0
  role   = aws_iam_role.replication[0].arn
  bucket = aws_s3_bucket.jenkins_backup.id

  rule {
    id     = "jenkins_backup_replication"
    status = "Enabled"

    destination {
      bucket        = aws_s3_bucket.jenkins_backup_replica[0].arn
      storage_class = "STANDARD_IA"
    }
  }

  depends_on = [aws_s3_bucket_versioning.jenkins_backup_versioning]
}

# IAM role for replication
resource "aws_iam_role" "replication" {
  count = var.enable_cross_region_replication ? 1 : 0
  name  = "${var.environment}-jenkins-s3-replication-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "replication" {
  count = var.enable_cross_region_replication ? 1 : 0
  name  = "${var.environment}-jenkins-s3-replication-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl"
        ]
        Effect = "Allow"
        Resource = "${aws_s3_bucket.jenkins_backup.arn}/*"
      },
      {
        Action = [
          "s3:ListBucket"
        ]
        Effect = "Allow"
        Resource = aws_s3_bucket.jenkins_backup.arn
      },
      {
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete"
        ]
        Effect = "Allow"
        Resource = "${aws_s3_bucket.jenkins_backup_replica[0].arn}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "replication" {
  count      = var.enable_cross_region_replication ? 1 : 0
  role       = aws_iam_role.replication[0].name
  policy_arn = aws_iam_policy.replication[0].arn
}

# CloudWatch metrics for monitoring
resource "aws_s3_bucket_metric" "jenkins_backup_metrics" {
  bucket = aws_s3_bucket.jenkins_backup.id
  name   = "jenkins-backup-metrics"
}

# Notification for backup events (commented out for now)
# resource "aws_s3_bucket_notification" "jenkins_backup_notification" {
#   bucket = aws_s3_bucket.jenkins_backup.id
# 
#   topic {
#     topic_arn = var.sns_topic_arn
#     events    = ["s3:ObjectCreated:*", "s3:ObjectRemoved:*"]
#   }
# }
