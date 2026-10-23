variable "project_name" {
  description = "Project name."
  type        = string
  default     = "moment"
}

variable "env" {
  description = "Terraform environment name."
  type        = string
  default     = "shared"
}

variable "primary_region" {
  description = "Primary AWS region."
  type        = string
  default     = "ap-northeast-3"
}

variable "enable_common_iam" {
  description = "Whether to manage common IAM roles and policies from this environment. Keep false until migration is approved."
  type        = bool
  default     = false
}

variable "iam_resource_environment" {
  description = "Environment name passed to IAM module resource naming. Keep dev during migration to avoid replacing existing moment-dev-* IAM resources."
  type        = string
  default     = "dev"
}

variable "github_repository" {
  description = "GitHub repository allowed to assume GitHub Actions role."
  type        = string
  default     = "Team-msp-architect-2026/msp-team04-infra"
}

variable "github_default_branch" {
  description = "Default branch allowed to assume GitHub Actions role."
  type        = string
  default     = "develop"
}

variable "github_oidc_allowed_subjects" {
  description = "GitHub OIDC sub conditions allowed to assume GitHub Actions role."
  type        = list(string)
  default = [
    "repo:Team-msp-architect-2026/msp-team04-infra:ref:refs/heads/develop"
  ]
}

variable "create_github_oidc_provider" {
  description = "Whether to create GitHub Actions OIDC Provider. Keep false when provider already exists."
  type        = bool
  default     = false
}

variable "github_oidc_provider_arn" {
  description = "Existing GitHub Actions OIDC Provider ARN."
  type        = string
  default     = "arn:aws:iam::611058323802:oidc-provider/token.actions.githubusercontent.com"
}

variable "ecr_repository_arns" {
  description = "Dev/Prod ECR repository ARNs supplied from dev/prod environments."
  type        = map(string)
  default     = {}
}

variable "raw_bucket_access_policy_arns" {
  description = "Raw bucket access policy ARNs for environment-specific Dev/Prod raw buckets."
  type        = list(string)
  default     = []
}

variable "sqs_queue_arns" {
  description = "SQS queue ARNs for Batch consume and Lambda send permissions."
  type        = list(string)
  default     = []
}

variable "opensearch_domain_arns" {
  description = "OpenSearch domain ARNs for AI Service access."
  type        = list(string)
  default     = []
}

variable "attach_lambda_raw_bucket_policy" {
  description = "Whether to attach the raw bucket access policy to the Lambda collector role."
  type        = bool
  default     = false
}

variable "enable_lambda_collector_secrets_manager_read" {
  description = "Whether Lambda Collector can read public data API keys from Secrets Manager."
  type        = bool
  default     = false
}
