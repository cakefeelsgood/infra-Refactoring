variable "project_name" {
  description = "Project name used for RDS resource naming."
  type        = string
}

variable "environment" {
  description = "Environment name for RDS resources."
  type        = string
}

variable "identifier" {
  description = "RDS DB instance identifier."
  type        = string
}

variable "database_name" {
  description = "Initial PostgreSQL database name."
  type        = string
  default     = "moment"
}

variable "master_username" {
  description = "PostgreSQL master username."
  type        = string
  default     = "moment_admin"
}

variable "subnet_ids" {
  description = "Private data subnet IDs where RDS is placed."
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security group IDs attached to RDS."
  type        = list(string)
}

variable "engine_version" {
  description = "PostgreSQL engine version."
  type        = string
  default     = "17.10"
}

variable "parameter_group_family" {
  description = "PostgreSQL parameter group family."
  type        = string
  default     = "postgres17"
}

variable "instance_class" {
  description = "RDS instance class for practice and validation."
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "Allocated storage size in GiB."
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Maximum storage size in GiB for autoscaling."
  type        = number
  default     = 100
}

variable "storage_type" {
  description = "RDS storage type."
  type        = string
  default     = "gp3"
}

variable "storage_encrypted" {
  description = "Whether RDS storage encryption is enabled."
  type        = bool
  default     = true
}

variable "port" {
  description = "PostgreSQL port."
  type        = number
  default     = 5432
}

variable "multi_az" {
  description = "Whether Multi-AZ deployment is enabled."
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Backup retention period in days."
  type        = number
  default     = 1
}

variable "backup_window" {
  description = "Preferred backup window."
  type        = string
  default     = "18:00-19:00"
}

variable "maintenance_window" {
  description = "Preferred maintenance window."
  type        = string
  default     = "sun:19:00-sun:20:00"
}

variable "deletion_protection" {
  description = "Whether deletion protection is enabled."
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Whether to skip final snapshot on destroy."
  type        = bool
  default     = true
}

variable "final_snapshot_identifier" {
  description = "Final snapshot identifier when skip_final_snapshot is false."
  type        = string
  default     = null
}

variable "auto_minor_version_upgrade" {
  description = "Whether minor engine version upgrades are applied automatically."
  type        = bool
  default     = true
}

variable "delete_automated_backups" {
  description = "Whether automated backups are deleted after DB deletion."
  type        = bool
  default     = true
}

variable "performance_insights_enabled" {
  description = "Whether Performance Insights is enabled."
  type        = bool
  default     = false
}

variable "parameters" {
  description = "Custom PostgreSQL parameter overrides."
  type        = map(string)
  default     = {}
}

variable "common_tags" {
  description = "Common tags applied to RDS resources."
  type        = map(string)
  default     = {}
}
