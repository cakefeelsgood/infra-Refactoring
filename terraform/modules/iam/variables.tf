variable "project_name" {
  description = "Project name used for IAM naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "common_tags" {
  description = "Common tags applied to IAM resources"
  type        = map(string)
  default     = {}
}

variable "github_repository" {
  description = "GitHub repository allowed to assume GitHub Actions role. Format: org/repo"
  type        = string
}

variable "github_default_branch" {
  description = "Default branch allowed to assume GitHub Actions role when github_oidc_allowed_subjects is empty"
  type        = string
  default     = "develop"
}

variable "github_oidc_allowed_subjects" {
  description = "GitHub OIDC sub conditions allowed to assume the GitHub Actions role"
  type        = list(string)
  default     = []
}

variable "create_github_oidc_provider" {
  description = "Whether to create GitHub Actions OIDC Provider"
  type        = bool
  default     = true
}

variable "github_oidc_provider_arn" {
  description = "Existing GitHub Actions OIDC Provider ARN. Use when provider already exists in the account"
  type        = string
  default     = null
}

variable "create_eks_oidc_provider" {
  description = "Whether to create EKS OIDC Provider. Requires eks_oidc_issuer_url"
  type        = bool
  default     = false
}

variable "eks_oidc_issuer_url" {
  description = "EKS cluster OIDC issuer URL"
  type        = string
  default     = ""
}

variable "eks_oidc_provider_arn" {
  description = "Existing EKS OIDC Provider ARN. Use after EKS cluster is created"
  type        = string
  default     = null
}

variable "eks_oidc_provider_url" {
  description = "Existing EKS OIDC Provider URL without https://. Required when eks_oidc_provider_arn is provided"
  type        = string
  default     = ""
}

variable "enable_irsa_roles" {
  description = "Whether to create IRSA roles. Keep false until EKS OIDC Provider is available"
  type        = bool
  default     = false
}

variable "irsa_service_accounts" {
  description = "Kubernetes ServiceAccounts mapped to IRSA roles"
  type = map(object({
    namespace = string
    name      = string
  }))

  default = {
    aws_load_balancer_controller = {
      namespace = "kube-system"
      name      = "aws-load-balancer-controller"
    }
    backend = {
      namespace = "moment"
      name      = "backend-api"
    }
    batch = {
      namespace = "moment"
      name      = "batch-job"
    }
    ai_service = {
      namespace = "moment"
      name      = "ai-service"
    }
  }
}

variable "ecr_repository_arns" {
  description = "ECR repository ARNs used by GitHub Actions and workloads"
  type        = map(string)
  default     = {}
}

variable "raw_bucket_access_policy_arn" {
  description = "Deprecated single IAM policy ARN for raw S3 bucket access. Prefer raw_bucket_access_policy_arns."
  type        = string
  default     = null
}

variable "raw_bucket_access_policy_arns" {
  description = "IAM policy ARNs for environment-specific raw S3 bucket access."
  type        = list(string)
  default     = []
}

variable "raw_bucket_access_policy_arn_map" {
  description = "Static-key IAM policy ARN map for environment-specific raw S3 bucket access. Keys must be known at plan time; values may be known after apply."
  type        = map(string)
  default     = {}
}

variable "enable_sqs_queue_policy_statements" {
  description = "Whether to include SQS queue policy statements for Batch and Lambda Collector. Use a known boolean instead of deriving count from unknown queue ARNs."
  type        = bool
  default     = false
}

variable "sqs_queue_arns" {
  description = "SQS queue ARNs for Batch consume and Lambda send permissions"
  type        = list(string)
  default     = []
}

variable "enable_lambda_collector_secrets_manager_read" {
  description = "Whether Lambda Collector can read public data API keys from Secrets Manager."
  type        = bool
  default     = false
}

variable "opensearch_domain_arns" {
  description = "OpenSearch domain ARNs for AI Service access"
  type        = list(string)
  default     = []
}

variable "profile_image_bucket_arns" {
  description = "Profile image S3 bucket ARNs that Backend API pod can upload to."
  type        = list(string)
  default     = []
}

variable "profile_image_object_key_prefix" {
  description = "S3 object key prefix for Backend profile image uploads."
  type        = string
  default     = "uploads/profile"
}

variable "notification_sns_topic_arns" {
  description = "Notification SNS topic ARNs that Backend API pod can publish to."
  type        = list(string)
  default     = []
}


variable "attach_lambda_raw_bucket_policy" {
  description = "Whether to attach the raw bucket access policy to the Lambda collector role."
  type        = bool
  default     = false
}
