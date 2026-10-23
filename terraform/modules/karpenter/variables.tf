variable "project_name" {
  description = "Project name used for Karpenter resource naming."
  type        = string
}

variable "environment" {
  description = "Environment name. Example: prod."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name that Karpenter manages nodes for."
  type        = string
}

variable "eks_oidc_provider_arn" {
  description = "EKS OIDC provider ARN for the Karpenter controller IRSA role."
  type        = string
}

variable "eks_oidc_provider_url" {
  description = "EKS OIDC provider URL without https://."
  type        = string
}

variable "controller_namespace" {
  description = "Kubernetes namespace of the Karpenter controller ServiceAccount."
  type        = string
  default     = "kube-system"
}

variable "controller_service_account_name" {
  description = "Kubernetes ServiceAccount name of the Karpenter controller."
  type        = string
  default     = "karpenter"
}

variable "cluster_security_group_id" {
  description = "EKS cluster primary security group ID. Karpenter nodes use it like the managed node groups do, so it gets the discovery tag."
  type        = string
}

variable "node_additional_policy_arns" {
  description = "Additional IAM policy ARNs attached to the Karpenter node role."
  type        = map(string)
  default     = {}
}

variable "common_tags" {
  description = "Common tags applied to Karpenter resources."
  type        = map(string)
  default     = {}
}
