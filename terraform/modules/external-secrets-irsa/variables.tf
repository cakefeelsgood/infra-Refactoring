variable "project_name" {
  description = "Project name used for resource naming."
  type        = string
}

variable "environment" {
  description = "Environment name."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace where External Secrets Operator runs."
  type        = string
  default     = "external-secrets"
}

variable "service_account_name" {
  description = "Kubernetes ServiceAccount name used by External Secrets Operator."
  type        = string
  default     = "external-secrets"
}

variable "eks_oidc_provider_arn" {
  description = "EKS OIDC provider ARN."
  type        = string
}

variable "eks_oidc_provider_url" {
  description = "EKS OIDC provider URL without https://."
  type        = string
}

variable "secret_arns" {
  description = "AWS Secrets Manager secret ARNs that External Secrets Operator can read."
  type        = list(string)
  default     = []
}

variable "allow_rds_managed_secrets" {
  description = "Whether to allow reading RDS managed master-user secrets named rds!db-*."
  type        = bool
  default     = false
}

variable "common_tags" {
  description = "Common tags applied to resources."
  type        = map(string)
  default     = {}
}
