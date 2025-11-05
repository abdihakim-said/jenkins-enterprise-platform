# EFS Module - Main Configuration
# Author: Abdihakim Said

# EFS File System
resource "aws_efs_file_system" "jenkins" {
  creation_token = "${var.environment}-${replace(lower(var.project_name), " ", "-")}-efs"
  
  performance_mode                = "generalPurpose"
  throughput_mode                 = "provisioned"
  provisioned_throughput_in_mibps = 100
  encrypted                       = true

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  lifecycle_policy {
    transition_to_primary_storage_class = "AFTER_1_ACCESS"
  }

  tags = merge(var.tags, {
    Name    = "${var.environment}-${replace(lower(var.project_name), " ", "-")}-efs"
    Type    = "Jenkins Shared Storage"
    Purpose = "Jenkins Shared Storage"
    Story   = "Story-2.3-EFS-Module"
  })
}

# EFS Mount Targets
resource "aws_efs_mount_target" "jenkins" {
  count = length(var.private_subnet_ids)

  file_system_id  = aws_efs_file_system.jenkins.id
  subnet_id       = var.private_subnet_ids[count.index]
  security_groups = [var.security_group_id]
}

# EFS Access Points
resource "aws_efs_access_point" "jenkins_home" {
  file_system_id = aws_efs_file_system.jenkins.id

  posix_user {
    gid = 1000
    uid = 1000
  }

  root_directory {
    path = "/jenkins"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "755"
    }
  }

  tags = merge(var.tags, {
    Name = "${var.environment}-${replace(lower(var.project_name), " ", "-")}-jenkins-home-ap"
    Type = "Jenkins Home Access Point"
  })
}

resource "aws_efs_access_point" "jenkins_workspace" {
  file_system_id = aws_efs_file_system.jenkins.id

  posix_user {
    gid = 1000
    uid = 1000
  }

  root_directory {
    path = "/workspace"
    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "755"
    }
  }

  tags = merge(var.tags, {
    Name = "${var.environment}-${replace(lower(var.project_name), " ", "-")}-jenkins-workspace-ap"
    Type = "Jenkins Workspace Access Point"
  })
}

# EFS Backup Policy
resource "aws_efs_backup_policy" "jenkins" {
  file_system_id = aws_efs_file_system.jenkins.id

  backup_policy {
    status = "ENABLED"
  }
}

# EFS File System Policy
resource "aws_efs_file_system_policy" "jenkins" {
  file_system_id = aws_efs_file_system.jenkins.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowRootAccess"
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action   = "elasticfilesystem:*"
        Resource = aws_efs_file_system.jenkins.arn
      }
    ]
  })
}
