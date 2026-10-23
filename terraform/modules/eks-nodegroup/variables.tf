variable "project_name" {
  description = "Project name used for EKS node group naming."
  type        = string
}

variable "environment" {
  description = "Environment name for this EKS node group module."
  type        = string
}

variable "cluster_name" {
  description = "Target EKS cluster name."
  type        = string
}

variable "node_role_arn" {
  description = "IAM role ARN used by EKS managed node groups."
  type        = string
}

variable "subnet_ids" {
  description = "Private app subnet IDs where EKS worker nodes are created."
  type        = list(string)
}

variable "node_groups" {
  description = "EKS managed node group definitions."
  type = map(object({
    name           = string
    capacity_type  = string
    instance_types = list(string)
    min_size       = number
    desired_size   = number
    max_size       = number
    disk_size      = number
    labels         = map(string)
    # kubelet maxPods. Must match the VPC CNI mode: set it together with
    # ENABLE_PREFIX_DELEGATION (checked by scripts/validation/check-pd-maxpods.sh).
    max_pods = optional(number)
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
}

variable "common_tags" {
  description = "Common tags applied to EKS node group resources."
  type        = map(string)
  default     = {}
}
