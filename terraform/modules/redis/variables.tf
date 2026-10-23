variable "project_name" {
  description = "Project name used for Redis resource naming."
  type        = string
}

variable "environment" {
  description = "Environment name for Redis resources."
  type        = string
}

variable "replication_group_id" {
  description = "ElastiCache Redis replication group ID."
  type        = string
}

variable "description" {
  description = "Description for the ElastiCache Redis replication group."
  type        = string
}

variable "subnet_ids" {
  description = "Private data subnet IDs where Redis is placed."
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security group IDs attached to Redis."
  type        = list(string)
}

variable "engine_version" {
  description = "Redis engine version."
  type        = string
  default     = "7.0"
}

variable "node_type" {
  description = "ElastiCache Redis node type."
  type        = string
  default     = "cache.t3.micro"
}

variable "port" {
  description = "Redis port."
  type        = number
  default     = 6379
}

variable "parameter_group_name" {
  description = "Redis parameter group name."
  type        = string
  default     = "default.redis7"
}

variable "automatic_failover_enabled" {
  description = "Whether automatic failover is enabled."
  type        = bool
  default     = false
}

variable "multi_az_enabled" {
  description = "Whether Multi-AZ is enabled."
  type        = bool
  default     = false
}

variable "at_rest_encryption_enabled" {
  description = "Whether encryption at rest is enabled."
  type        = bool
  default     = true
}

variable "transit_encryption_enabled" {
  description = "Whether in-transit encryption is enabled. Disabled for simple redis-cli validation in M2."
  type        = bool
  default     = false
}

variable "num_cache_clusters" {
  description = "Number of cache clusters (nodes) in the replication group. Set to 2+ for HA with automatic failover."
  type        = number
  default     = 1
}

variable "snapshot_retention_limit" {
  description = "Number of days to retain Redis snapshots."
  type        = number
  default     = 0
}

variable "common_tags" {
  description = "Common tags applied to Redis resources."
  type        = map(string)
  default     = {}
}

variable "notification_topic_arn" {
  description = "SNS topic ARN for ElastiCache event notifications."
  type        = string
  default     = null
}
