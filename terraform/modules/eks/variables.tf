variable "project_name" {
  description = "Project name used for EKS resource naming."
  type        = string
}

variable "environment" {
  description = "Workload environment name for this EKS cluster. Example: prod."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "cluster_role_arn" {
  description = "IAM role ARN for the EKS control plane."
  type        = string
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version."
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for EKS control plane ENIs. Use Prod private app subnets for MoMent."
  type        = list(string)
}

variable "cluster_security_group_ids" {
  description = "Additional security group IDs for EKS control plane ENIs."
  type        = list(string)
  default     = []
}

variable "endpoint_private_access" {
  description = "Whether the EKS private API endpoint is enabled."
  type        = bool
  default     = true
}

variable "endpoint_public_access" {
  description = "Whether the EKS public API endpoint is enabled."
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "CIDR blocks allowed to access the EKS public API endpoint."
  type        = list(string)
}

variable "enabled_cluster_log_types" {
  description = "EKS control plane log types to enable."
  type        = list(string)
  default = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler"
  ]
}

variable "service_ipv4_cidr" {
  description = "Kubernetes service IPv4 CIDR."
  type        = string
  default     = "172.20.0.0/16"
}

variable "authentication_mode" {
  description = "EKS cluster authentication mode."
  type        = string
  default     = "API"

  validation {
    condition     = contains(["API", "API_AND_CONFIG_MAP"], var.authentication_mode)
    error_message = "authentication_mode must be API or API_AND_CONFIG_MAP."
  }
}

variable "bootstrap_cluster_creator_admin_permissions" {
  description = "Whether to grant the cluster creator admin permissions automatically."
  type        = bool
  default     = false
}

variable "cluster_admin_principal_arn" {
  description = "Primary IAM principal ARN to grant EKS cluster admin access through EKS Access Entry."
  type        = string
}

variable "cluster_admin_additional_principal_arns" {
  description = "Additional IAM principal ARNs to grant EKS cluster admin access through EKS Access Entry."
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for principal_arn in var.cluster_admin_additional_principal_arns :
      length(trimspace(principal_arn)) > 0
    ])
    error_message = "cluster_admin_additional_principal_arns must not contain empty values."
  }
}

variable "cluster_admin_access_policy_arn" {
  description = "EKS access policy ARN for cluster admin."
  type        = string
  default     = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
}

variable "addons" {
  description = "EKS managed add-ons to install. NodeGroup is intentionally out of scope for M2-EKS-01."
  type = map(object({
    addon_version               = string
    configuration_values        = optional(string)
    service_account_role_arn    = optional(string)
    resolve_conflicts_on_create = optional(string, "OVERWRITE")
    resolve_conflicts_on_update = optional(string, "OVERWRITE")
  }))
  default = {}
}

variable "create_eks_oidc_provider" {
  description = "Whether to create IAM OIDC Provider for this EKS cluster."
  type        = bool
  default     = true
}

variable "enable_ebs_csi_irsa" {
  description = "Whether to create an IRSA role for the aws-ebs-csi-driver add-on."
  type        = bool
  default     = true
}

variable "ebs_csi_service_account_namespace" {
  description = "Kubernetes namespace for EBS CSI controller ServiceAccount."
  type        = string
  default     = "kube-system"
}

variable "ebs_csi_service_account_name" {
  description = "Kubernetes ServiceAccount name for EBS CSI controller."
  type        = string
  default     = "ebs-csi-controller-sa"
}

variable "ebs_csi_policy_arn" {
  description = "IAM policy ARN attached to the EBS CSI IRSA role."
  type        = string
  default     = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

variable "common_tags" {
  description = "Common tags applied to EKS resources."
  type        = map(string)
  default     = {}
}
