variable "project_name" {
  description = "Project name used for resource naming."
  type        = string
}

variable "environment" {
  description = "Environment name."
  type        = string
}

variable "eks_oidc_provider_arn" {
  description = "EKS OIDC provider ARN."
  type        = string
}

variable "eks_oidc_provider_url" {
  description = "EKS OIDC provider URL without https://."
  type        = string
}

variable "service_accounts" {
  description = "Kubernetes ServiceAccounts mapped to workload IRSA roles."
  type = map(object({
    namespace = string
    name      = string
  }))
}

variable "policy_arns_by_service_account" {
  description = "IAM policy ARNs attached to each workload IRSA role. Map keys must be statically known at plan time."
  type        = map(map(string))
  default     = {}
}

variable "common_tags" {
  description = "Common tags applied to resources."
  type        = map(string)
  default     = {}
}
