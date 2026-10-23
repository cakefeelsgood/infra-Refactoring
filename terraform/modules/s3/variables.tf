variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "bucket_name" {
  description = "Optional explicit S3 bucket name"
  type        = string
  default     = null
}

variable "force_destroy" {
  description = "Whether to force destroy bucket even if objects exist"
  type        = bool
  default     = false
}

variable "raw_expiration_days" {
  description = "Expiration days for raw data"
  type        = number
  default     = 90
}

variable "processed_expiration_days" {
  description = "Expiration days for processed data"
  type        = number
  default     = 180
}

variable "failed_expiration_days" {
  description = "Expiration days for failed data"
  type        = number
  default     = 30
}

variable "common_tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
