# Storage Module Variables
# Jenkins Enterprise Platform - Storage Module
# Version: 2.0

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for EFS resources"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for EFS mount targets"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs that should have access to EFS"
  type        = list(string)
}

# S3 Configuration
variable "backup_retention_days" {
  description = "Number of days to retain backups in S3"
  type        = number
  default     = 30
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 365
    error_message = "Backup retention days must be between 1 and 365."
  }
}

# EFS Configuration
variable "enable_efs" {
  description = "Enable EFS for persistent Jenkins storage"
  type        = bool
  default     = true
}

variable "efs_performance_mode" {
  description = "EFS performance mode"
  type        = string
  default     = "generalPurpose"
  validation {
    condition     = can(regex("^(generalPurpose|maxIO)$", var.efs_performance_mode))
    error_message = "EFS performance mode must be either 'generalPurpose' or 'maxIO'."
  }
}

variable "efs_throughput_mode" {
  description = "EFS throughput mode"
  type        = string
  default     = "bursting"
  validation {
    condition     = can(regex("^(bursting|provisioned)$", var.efs_throughput_mode))
    error_message = "EFS throughput mode must be either 'bursting' or 'provisioned'."
  }
}

variable "efs_provisioned_throughput" {
  description = "Provisioned throughput in MiB/s (only used when throughput_mode is provisioned)"
  type        = number
  default     = null
  validation {
    condition     = var.efs_provisioned_throughput == null || (var.efs_provisioned_throughput >= 1 && var.efs_provisioned_throughput <= 1024)
    error_message = "Provisioned throughput must be between 1 and 1024 MiB/s."
  }
}

variable "efs_encryption_enabled" {
  description = "Enable encryption at rest for EFS"
  type        = bool
  default     = true
}

variable "efs_kms_key_id" {
  description = "KMS key ID for EFS encryption (if not provided, AWS managed key will be used)"
  type        = string
  default     = null
}

variable "efs_backup_enabled" {
  description = "Enable automatic backups for EFS"
  type        = bool
  default     = true
}

variable "efs_transition_to_ia" {
  description = "Lifecycle policy for transitioning files to Infrequent Access storage class"
  type        = string
  default     = "AFTER_30_DAYS"
  validation {
    condition = can(regex("^(AFTER_7_DAYS|AFTER_14_DAYS|AFTER_30_DAYS|AFTER_60_DAYS|AFTER_90_DAYS)$", var.efs_transition_to_ia))
    error_message = "Transition to IA must be one of: AFTER_7_DAYS, AFTER_14_DAYS, AFTER_30_DAYS, AFTER_60_DAYS, AFTER_90_DAYS."
  }
}

variable "efs_transition_to_primary_storage_class" {
  description = "Lifecycle policy for transitioning files back to primary storage class"
  type        = string
  default     = "AFTER_1_ACCESS"
  validation {
    condition = can(regex("^(AFTER_1_ACCESS)$", var.efs_transition_to_primary_storage_class))
    error_message = "Transition to primary storage class must be AFTER_1_ACCESS."
  }
}

variable "jenkins_uid" {
  description = "UID for Jenkins user"
  type        = number
  default     = 1000
}

variable "jenkins_gid" {
  description = "GID for Jenkins group"
  type        = number
  default     = 1000
}

variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 30
  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch retention period."
  }
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
