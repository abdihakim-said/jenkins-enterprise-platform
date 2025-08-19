# Storage Module - Jenkins Enterprise Platform
# Creates S3 buckets for backups and EFS for persistent storage
# Version: 2.0

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Random ID for unique bucket naming
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# S3 Bucket for Jenkins backups
resource "aws_s3_bucket" "jenkins_backup" {
  bucket = "${var.environment}-${var.project_name}-backup-${random_id.bucket_suffix.hex}"
  
  tags = merge(var.common_tags, {
    Name = "${var.environment}-${var.project_name}-backup-bucket"
    Type = "Jenkins Backup Bucket"
  })
}

resource "aws_s3_bucket_versioning" "jenkins_backup" {
  bucket = aws_s3_bucket.jenkins_backup.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_encryption" "jenkins_backup" {
  bucket = aws_s3_bucket.jenkins_backup.id
  
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "jenkins_backup" {
  bucket = aws_s3_bucket.jenkins_backup.id
  
  rule {
    id     = "backup_lifecycle"
    status = "Enabled"
    
    expiration {
      days = var.backup_retention_days
    }
    
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
    
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_public_access_block" "jenkins_backup" {
  bucket = aws_s3_bucket.jenkins_backup.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# EFS File System (conditional)
resource "aws_efs_file_system" "jenkins_efs" {
  count = var.enable_efs ? 1 : 0
  
  creation_token = "${var.environment}-${var.project_name}-efs"
  
  performance_mode                = var.efs_performance_mode
  throughput_mode                 = var.efs_throughput_mode
  provisioned_throughput_in_mibps = var.efs_throughput_mode == "provisioned" ? var.efs_provisioned_throughput : null
  
  encrypted  = var.efs_encryption_enabled
  kms_key_id = var.efs_kms_key_id
  
  enable_backup_policy = var.efs_backup_enabled

  lifecycle_policy {
    transition_to_ia                    = var.efs_transition_to_ia
    transition_to_primary_storage_class = var.efs_transition_to_primary_storage_class
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-${var.project_name}-efs"
    Type = "Jenkins EFS"
  })
}

# EFS Mount Targets
resource "aws_efs_mount_target" "jenkins_efs_mount" {
  count = var.enable_efs ? length(var.private_subnet_ids) : 0
  
  file_system_id  = aws_efs_file_system.jenkins_efs[0].id
  subnet_id       = var.private_subnet_ids[count.index]
  security_groups = [aws_security_group.efs_sg[0].id]
}

# Security Group for EFS
resource "aws_security_group" "efs_sg" {
  count = var.enable_efs ? 1 : 0
  
  name_prefix = "${var.environment}-${var.project_name}-efs-"
  vpc_id      = var.vpc_id
  description = "Security group for Jenkins EFS mount targets"

  ingress {
    description     = "NFS from Jenkins instances"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = var.security_group_ids
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-${var.project_name}-efs-sg"
    Type = "EFS Security Group"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# EFS Access Points
resource "aws_efs_access_point" "jenkins_home" {
  count = var.enable_efs ? 1 : 0
  
  file_system_id = aws_efs_file_system.jenkins_efs[0].id
  
  posix_user {
    gid = var.jenkins_gid
    uid = var.jenkins_uid
  }
  
  root_directory {
    path = "/jenkins-home"
    creation_info {
      owner_gid   = var.jenkins_gid
      owner_uid   = var.jenkins_uid
      permissions = "0755"
    }
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-${var.project_name}-jenkins-home-ap"
    Type = "Jenkins Home Access Point"
  })
}

resource "aws_efs_access_point" "jenkins_builds" {
  count = var.enable_efs ? 1 : 0
  
  file_system_id = aws_efs_file_system.jenkins_efs[0].id
  
  posix_user {
    gid = var.jenkins_gid
    uid = var.jenkins_uid
  }
  
  root_directory {
    path = "/jenkins-builds"
    creation_info {
      owner_gid   = var.jenkins_gid
      owner_uid   = var.jenkins_uid
      permissions = "0755"
    }
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-${var.project_name}-jenkins-builds-ap"
    Type = "Jenkins Builds Access Point"
  })
}

# EFS Backup Policy
resource "aws_efs_backup_policy" "jenkins_efs_backup" {
  count = var.enable_efs && var.efs_backup_enabled ? 1 : 0
  
  file_system_id = aws_efs_file_system.jenkins_efs[0].id

  backup_policy {
    status = "ENABLED"
  }
}

# CloudWatch Log Group for EFS Performance Monitoring
resource "aws_cloudwatch_log_group" "efs_performance" {
  count = var.enable_efs ? 1 : 0
  
  name              = "/aws/efs/${aws_efs_file_system.jenkins_efs[0].id}"
  retention_in_days = var.log_retention_days

  tags = merge(var.common_tags, {
    Name = "${var.environment}-${var.project_name}-efs-logs"
    Type = "EFS Log Group"
  })
}

# SSM Parameters for EFS (if enabled)
resource "aws_ssm_parameter" "efs_id" {
  count = var.enable_efs ? 1 : 0
  
  name        = "/${var.project_name}/efs-id"
  description = "EFS File System ID for Jenkins data persistence"
  type        = "String"
  value       = aws_efs_file_system.jenkins_efs[0].id

  tags = merge(var.common_tags, {
    Name = "${var.environment}-${var.project_name}-efs-id-param"
    Type = "EFS Parameter"
  })
}

resource "aws_ssm_parameter" "efs_dns_name" {
  count = var.enable_efs ? 1 : 0
  
  name        = "/${var.project_name}/efs-dns-name"
  description = "EFS DNS name for mounting"
  type        = "String"
  value       = aws_efs_file_system.jenkins_efs[0].dns_name

  tags = merge(var.common_tags, {
    Name = "${var.environment}-${var.project_name}-efs-dns-param"
    Type = "EFS Parameter"
  })
}

# SSM Parameter for S3 backup bucket
resource "aws_ssm_parameter" "s3_backup_bucket" {
  name        = "/${var.project_name}/s3-backup-bucket"
  description = "S3 bucket name for Jenkins backups"
  type        = "String"
  value       = aws_s3_bucket.jenkins_backup.bucket

  tags = merge(var.common_tags, {
    Name = "${var.environment}-${var.project_name}-s3-backup-param"
    Type = "S3 Parameter"
  })
}
