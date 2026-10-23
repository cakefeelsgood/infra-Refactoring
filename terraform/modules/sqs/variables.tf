variable "project_name" {
  description = "Project name used for SQS resource naming."
  type        = string
}

variable "environment" {
  description = "Environment name for SQS resources."
  type        = string
}

variable "queue_name" {
  description = "SQS main queue name."
  type        = string
}

variable "dlq_name" {
  description = "SQS dead-letter queue name."
  type        = string
}

variable "visibility_timeout_seconds" {
  description = "Visibility timeout for SQS messages in seconds."
  type        = number
  default     = 300
}

variable "message_retention_seconds" {
  description = "Message retention period for the main SQS queue in seconds."
  type        = number
  default     = 345600
}

variable "dlq_message_retention_seconds" {
  description = "Message retention period for the SQS dead-letter queue in seconds."
  type        = number
  default     = 1209600
}

variable "max_receive_count" {
  description = "Number of receives before moving a message to the DLQ."
  type        = number
  default     = 3
}

variable "receive_wait_time_seconds" {
  description = "Long polling wait time for SQS receive calls in seconds."
  type        = number
  default     = 10
}

variable "delay_seconds" {
  description = "Delay for new SQS messages in seconds."
  type        = number
  default     = 0
}

variable "max_message_size" {
  description = "Maximum SQS message size in bytes."
  type        = number
  default     = 262144
}

variable "sqs_managed_sse_enabled" {
  description = "Whether SQS managed server-side encryption is enabled."
  type        = bool
  default     = true
}

variable "common_tags" {
  description = "Common tags applied to SQS resources."
  type        = map(string)
  default     = {}
}
