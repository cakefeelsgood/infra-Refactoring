variable "project_name" {
  description = "Project name used for resource naming."
  type        = string
}

variable "environment" {
  description = "Environment name."
  type        = string
}

variable "lambda_function_name" {
  description = "Lambda Collector function name."
  type        = string
}

variable "lambda_role_arn" {
  description = "IAM role ARN used by Lambda Collector."
  type        = string
}

variable "raw_bucket_name" {
  description = "Raw data S3 bucket name."
  type        = string
}

variable "queue_url" {
  description = "SQS main queue URL."
  type        = string
}

variable "public_data_api_url" {
  description = "Legacy single Public Data API URL. Prefer public_data_sources_json for M2-DATA-02."
  type        = string
  default     = ""
}

variable "public_data_sources_json" {
  description = "Legacy inline JSON array of public data source configs. Prefer public_data_sources_secret_name when source config is large."
  type        = string
  default     = "[]"

  validation {
    condition     = can(jsondecode(var.public_data_sources_json))
    error_message = "public_data_sources_json must be valid JSON."
  }
}

variable "public_data_sources_secret_name" {
  description = "Secrets Manager secret name containing public data source configs."
  type        = string
  default     = ""
}

variable "schedule_expression" {
  description = "EventBridge Scheduler expression."
  type        = string
  default     = "rate(1 day)"
}

variable "schedule_state" {
  description = "EventBridge Scheduler state."
  type        = string
  default     = "DISABLED"
}

variable "lambda_runtime" {
  description = "Lambda runtime."
  type        = string
  default     = "python3.12"
}

variable "lambda_timeout" {
  description = "Lambda timeout in seconds."
  type        = number
  default     = 30
}

variable "lambda_memory_size" {
  description = "Lambda memory size in MB."
  type        = number
  default     = 128
}

variable "log_retention_days" {
  description = "CloudWatch log retention days for Lambda Collector."
  type        = number
  default     = 14
}

variable "common_tags" {
  description = "Common tags applied to resources."
  type        = map(string)
  default     = {}
}
