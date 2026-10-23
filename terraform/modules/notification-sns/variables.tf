variable "project_name" {
  description = "Project name used for notification SNS topic naming."
  type        = string
}

variable "environment" {
  description = "Environment name for notification SNS topic."
  type        = string
}

variable "topic_name" {
  description = "Optional explicit SNS topic name. Keep null to use the module naming convention."
  type        = string
  default     = null
}

variable "display_name" {
  description = "SNS topic display name."
  type        = string
  default     = "MoMent Notification"
}

variable "kms_master_key_id" {
  description = "Optional KMS key ID or alias for SNS topic server-side encryption. Keep null to avoid creating or coupling a KMS key in this module."
  type        = string
  default     = null
}

variable "common_tags" {
  description = "Common tags applied to notification SNS resources."
  type        = map(string)
  default     = {}
}
