# S3 Backup Module Variables
# Epic 3: Story 4.3 - S3 bucket configuration variables

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "jenkins-enterprise-platform"
}

variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
  
  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "Environment must be one of: dev, staging, production."
  }
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Bucket Configuration
variable "force_destroy_bucket" {
  description = "Allow bucket to be destroyed even if it contains objects"
  type        = bool
  default     = false
}

variable "enable_versioning" {
  description = "Enable S3 bucket versioning"
  type        = bool
  default     = true
}

# Lifecycle Configuration
variable "backup_retention_days" {
  description = "Number of days to retain backup files"
  type        = number
  default     = 90
  
  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 3650
    error_message = "Backup retention days must be between 1 and 3650."
  }
}

variable "log_retention_days" {
  description = "Number of days to retain log files"
  type        = number
  default     = 30
  
  validation {
    condition     = var.log_retention_days >= 1 && var.log_retention_days <= 365
    error_message = "Log retention days must be between 1 and 365."
  }
}

variable "transition_to_ia_days" {
  description = "Number of days before transitioning to IA storage class"
  type        = number
  default     = 30
  
  validation {
    condition     = var.transition_to_ia_days >= 30
    error_message = "Transition to IA must be at least 30 days."
  }
}

variable "transition_to_glacier_days" {
  description = "Number of days before transitioning to Glacier storage class"
  type        = number
  default     = 90
  
  validation {
    condition     = var.transition_to_glacier_days >= 90
    error_message = "Transition to Glacier must be at least 90 days."
  }
}

variable "transition_to_deep_archive_days" {
  description = "Number of days before transitioning to Deep Archive storage class"
  type        = number
  default     = 365
  
  validation {
    condition     = var.transition_to_deep_archive_days >= 180
    error_message = "Transition to Deep Archive must be at least 180 days."
  }
}

# Security Configuration
variable "jenkins_role_arn" {
  description = "ARN of the Jenkins IAM role for bucket access"
  type        = string
}

variable "kms_deletion_window" {
  description = "KMS key deletion window in days"
  type        = number
  default     = 7
  
  validation {
    condition     = var.kms_deletion_window >= 7 && var.kms_deletion_window <= 30
    error_message = "KMS deletion window must be between 7 and 30 days."
  }
}

# Monitoring Configuration
variable "enable_backup_monitoring" {
  description = "Enable CloudWatch monitoring for backups"
  type        = bool
  default     = true
}

variable "enable_backup_notifications" {
  description = "Enable S3 event notifications"
  type        = bool
  default     = true
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for backup notifications"
  type        = string
  default     = ""
}

variable "jenkins_log_group_name" {
  description = "CloudWatch log group name for Jenkins"
  type        = string
  default     = "/jenkins/application"
}

variable "alarm_actions" {
  description = "List of ARNs to notify when alarm triggers"
  type        = list(string)
  default     = []
}

# Inventory Configuration
variable "enable_inventory" {
  description = "Enable S3 inventory for the backup bucket"
  type        = bool
  default     = true
}

# Cross-Region Replication
variable "enable_cross_region_replication" {
  description = "Enable cross-region replication for disaster recovery"
  type        = bool
  default     = false
}

variable "replication_destination_bucket" {
  description = "Destination bucket for cross-region replication"
  type        = string
  default     = ""
}

variable "replication_destination_region" {
  description = "Destination region for cross-region replication"
  type        = string
  default     = ""
}

# Access Logging
variable "enable_access_logging" {
  description = "Enable S3 access logging"
  type        = bool
  default     = true
}

variable "access_log_bucket" {
  description = "S3 bucket for access logs"
  type        = string
  default     = ""
}

variable "access_log_prefix" {
  description = "Prefix for access log objects"
  type        = string
  default     = "access-logs/"
}

# Backup Configuration
variable "backup_schedule" {
  description = "Cron expression for backup schedule"
  type        = string
  default     = "0 2 * * *"  # Daily at 2 AM
}

variable "backup_types" {
  description = "Types of backups to perform"
  type        = list(string)
  default     = ["full", "incremental", "configuration"]
}

variable "backup_compression" {
  description = "Enable backup compression"
  type        = bool
  default     = true
}

variable "backup_encryption" {
  description = "Enable backup encryption before upload"
  type        = bool
  default     = true
}

# Performance Configuration
variable "multipart_threshold" {
  description = "Threshold for multipart uploads in bytes"
  type        = number
  default     = 104857600  # 100MB
}

variable "multipart_chunksize" {
  description = "Chunk size for multipart uploads in bytes"
  type        = number
  default     = 8388608  # 8MB
}

variable "max_concurrent_requests" {
  description = "Maximum number of concurrent requests"
  type        = number
  default     = 10
}

# Cost Optimization
variable "enable_intelligent_tiering" {
  description = "Enable S3 Intelligent Tiering"
  type        = bool
  default     = true
}

variable "enable_request_payer" {
  description = "Enable request payer (requester pays for requests)"
  type        = bool
  default     = false
}

# Compliance and Governance
variable "enable_object_lock" {
  description = "Enable S3 Object Lock for compliance"
  type        = bool
  default     = false
}

variable "object_lock_mode" {
  description = "Object Lock mode (GOVERNANCE or COMPLIANCE)"
  type        = string
  default     = "GOVERNANCE"
  
  validation {
    condition     = contains(["GOVERNANCE", "COMPLIANCE"], var.object_lock_mode)
    error_message = "Object Lock mode must be either GOVERNANCE or COMPLIANCE."
  }
}

variable "object_lock_retention_days" {
  description = "Object Lock retention period in days"
  type        = number
  default     = 30
}

# Disaster Recovery
variable "enable_point_in_time_recovery" {
  description = "Enable point-in-time recovery capabilities"
  type        = bool
  default     = true
}

variable "recovery_point_objective_hours" {
  description = "Recovery Point Objective in hours"
  type        = number
  default     = 24
}

variable "recovery_time_objective_hours" {
  description = "Recovery Time Objective in hours"
  type        = number
  default     = 4
}
