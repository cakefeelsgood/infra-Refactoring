variable "project_name" {
  description = "Project name used for alerting resource naming."
  type        = string
}

variable "environment" {
  description = "Environment name."
  type        = string
}

variable "sns_topic_name" {
  description = "Optional explicit CloudWatch alert SNS topic name."
  type        = string
  default     = null
}

variable "sns_display_name" {
  description = "SNS topic display name for CloudWatch alerts."
  type        = string
  default     = "MoMent Monitoring Alert"
}

variable "lambda_function_name" {
  description = "Optional explicit Slack notifier Lambda function name."
  type        = string
  default     = null
}

variable "lambda_runtime" {
  description = "Slack notifier Lambda runtime."
  type        = string
  default     = "python3.12"
}

variable "lambda_timeout" {
  description = "Slack notifier Lambda timeout in seconds."
  type        = number
  default     = 10
}

variable "lambda_memory_size" {
  description = "Slack notifier Lambda memory size in MB."
  type        = number
  default     = 128
}

variable "lambda_log_retention_days" {
  description = "CloudWatch Logs retention days for Slack notifier Lambda."
  type        = number
  default     = 14
}

variable "slack_webhook_secret_name" {
  description = "Secrets Manager secret name containing Slack webhook URL. Secret value is managed out-of-band."
  type        = string
}

variable "slack_webhook_secret_recovery_window_in_days" {
  description = "Recovery window in days for Slack webhook Secrets Manager secret."
  type        = number
  default     = 7
}

variable "enable_cloudwatch_alarms" {
  description = "Whether to create CloudWatch metric alarms."
  type        = bool
  default     = true
}

variable "enable_alarm_actions" {
  description = "Whether CloudWatch alarms should publish ALARM actions to SNS."
  type        = bool
  default     = true
}

variable "enable_ok_actions" {
  description = "Whether CloudWatch alarms should publish OK actions to SNS."
  type        = bool
  default     = true
}

variable "rds_instance_identifiers" {
  description = "RDS DBInstanceIdentifier values keyed by logical name."
  type        = map(string)
  default     = {}
}

variable "redis_replication_group_ids" {
  description = "ElastiCache ReplicationGroupId values keyed by logical name."
  type        = map(string)
  default     = {}
}

variable "opensearch_domain_names" {
  description = "OpenSearch domain names keyed by logical name."
  type        = map(string)
  default     = {}
}

variable "sqs_queue_names" {
  description = "SQS queue names keyed by logical name."
  type        = map(string)
  default     = {}
}

variable "sqs_dlq_names" {
  description = "SQS DLQ names keyed by logical name."
  type        = map(string)
  default     = {}
}

variable "lambda_function_names" {
  description = "Lambda function names keyed by logical name."
  type        = map(string)
  default     = {}
}

variable "rds_cpu_high_threshold" {
  description = "RDS CPUUtilization high threshold percent."
  type        = number
  default     = 80
}

variable "rds_free_storage_low_threshold_bytes" {
  description = "RDS FreeStorageSpace low threshold in bytes."
  type        = number
  default     = 2147483648
}

variable "redis_cpu_high_threshold" {
  description = "Redis CPUUtilization high threshold percent."
  type        = number
  default     = 80
}

variable "redis_evictions_threshold" {
  description = "Redis Evictions threshold."
  type        = number
  default     = 0
}

variable "sqs_visible_messages_high_threshold" {
  description = "SQS visible messages high threshold."
  type        = number
  default     = 100
}

variable "sqs_dlq_visible_messages_threshold" {
  description = "SQS DLQ visible messages threshold."
  type        = number
  default     = 0
}

variable "lambda_errors_threshold" {
  description = "Lambda Errors threshold."
  type        = number
  default     = 0
}

variable "common_tags" {
  description = "Common tags applied to alerting resources."
  type        = map(string)
  default     = {}
}

variable "application_load_balancer_tag_selectors" {
  description = "Application Load Balancer tag selectors keyed by logical name. Used for AWS Load Balancer Controller managed ALBs."
  type = map(object({
    tags = map(string)
  }))
  default = {}
}

variable "target_group_tag_selectors" {
  description = "Target Group tag selectors keyed by logical name. load_balancer_key must reference application_load_balancer_tag_selectors."
  type = map(object({
    load_balancer_key = string
    tags              = map(string)
  }))
  default = {}
}

variable "alb_elb_5xx_count_threshold" {
  description = "ALB HTTPCode_ELB_5XX_Count alarm threshold."
  type        = number
  default     = 1
}

variable "alb_target_response_time_high_threshold_seconds" {
  description = "ALB TargetResponseTime high threshold in seconds."
  type        = number
  default     = 2
}

variable "target_group_unhealthy_host_count_threshold" {
  description = "Target Group UnHealthyHostCount alarm threshold."
  type        = number
  default     = 0
}

variable "target_group_5xx_count_threshold" {
  description = "Target Group HTTPCode_Target_5XX_Count alarm threshold."
  type        = number
  default     = 1
}

# Full alert catalog extension thresholds.

variable "rds_connection_high_threshold" {
  description = "RDS DatabaseConnections high threshold."
  type        = number
  default     = 80
}

variable "redis_memory_high_threshold_percent" {
  description = "Redis DatabaseMemoryUsagePercentage high threshold percent."
  type        = number
  default     = 85
}

variable "lambda_throttles_threshold" {
  description = "Lambda Throttles threshold."
  type        = number
  default     = 0
}

variable "sqs_oldest_message_high_threshold_seconds" {
  description = "SQS ApproximateAgeOfOldestMessage high threshold in seconds."
  type        = number
  default     = 900
}

variable "opensearch_cpu_high_threshold" {
  description = "OpenSearch CPUUtilization high threshold percent."
  type        = number
  default     = 85
}

variable "opensearch_jvm_memory_pressure_high_threshold" {
  description = "OpenSearch JVMMemoryPressure high threshold percent."
  type        = number
  default     = 85
}

variable "opensearch_free_storage_low_threshold_mb" {
  description = "OpenSearch FreeStorageSpace low threshold in MiB."
  type        = number
  default     = 5120
}

variable "target_group_healthy_host_zero_threshold" {
  description = "Target Group HealthyHostCount low threshold."
  type        = number
  default     = 1
}
