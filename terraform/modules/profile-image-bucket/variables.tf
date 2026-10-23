variable "project_name" {
  description = "Project name used for profile image bucket naming."
  type        = string
}

variable "environment" {
  description = "Environment name for profile image bucket."
  type        = string
}

variable "bucket_name" {
  description = "Optional explicit profile image S3 bucket name. Keep null to use the module naming convention."
  type        = string
  default     = null
}

variable "object_key_prefix" {
  description = "S3 object key prefix used by Backend profile image upload."
  type        = string
  default     = "uploads/profile"
}

variable "force_destroy" {
  description = "Whether to force destroy bucket even if objects exist. Bucket still has prevent_destroy=true for safety."
  type        = bool
  default     = false
}

variable "versioning_enabled" {
  description = "Whether S3 bucket versioning is enabled."
  type        = bool
  default     = true
}

variable "noncurrent_version_expiration_days" {
  description = "Expiration days for noncurrent object versions."
  type        = number
  default     = 30
}

variable "abort_incomplete_multipart_upload_days" {
  description = "Days after initiation to abort incomplete multipart uploads."
  type        = number
  default     = 7
}

variable "cors_allowed_origins" {
  description = "Allowed origins for browser-based Presigned PUT uploads."
  type        = list(string)
  default     = []
}

variable "cors_allowed_methods" {
  description = "Allowed CORS methods for profile image upload."
  type        = list(string)
  default     = ["PUT"]
}

variable "cors_allowed_headers" {
  description = "Allowed CORS headers for profile image upload."
  type        = list(string)
  default     = ["Content-Type", "x-amz-*"]
}

variable "cors_expose_headers" {
  description = "Headers exposed to browser clients after upload."
  type        = list(string)
  default     = ["ETag"]
}

variable "cors_max_age_seconds" {
  description = "CORS preflight cache duration in seconds."
  type        = number
  default     = 3000
}

variable "common_tags" {
  description = "Common tags applied to profile image bucket resources."
  type        = map(string)
  default     = {}
}


variable "public_read_enabled" {
  description = "Whether profile image objects under object_key_prefix are publicly readable with s3:GetObject. Keep PutObject private and use Presigned PUT for uploads."
  type        = bool
  default     = false
}
