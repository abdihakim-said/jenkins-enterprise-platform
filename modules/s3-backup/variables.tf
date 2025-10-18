#---------------------------------------------#
# Jenkins Enterprise Platform - S3 Backup Variables
#---------------------------------------------#

variable "environment" {
  description = "Environment name (dev, staging, production)"
  type        = string
}

variable "kms_key_id" {
  description = "KMS key ID for S3 encryption"
  type        = string
  default     = null
}

variable "job_artifacts_retention_days" {
  description = "Number of days to retain job artifacts"
  type        = number
  default     = 90
}

variable "build_logs_retention_days" {
  description = "Number of days to retain build logs"
  type        = number
  default     = 30
}

variable "enable_cross_region_replication" {
  description = "Enable cross-region replication for disaster recovery"
  type        = bool
  default     = true
}

variable "replica_region" {
  description = "AWS region for backup replication"
  type        = string
  default     = "us-west-2"
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for backup notifications"
  type        = string
  default     = ""
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
