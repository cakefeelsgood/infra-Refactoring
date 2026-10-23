variable "project_name" {
  description = "Project name."
  type        = string
}

variable "env" {
  description = "Workload environment name. Example: dev."
  type        = string
}

variable "vpc_cidr" {
  description = "Dev VPC CIDR block."
  type        = string
}

variable "availability_zones" {
  description = "Availability zones for subnet creation."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDR blocks for internet-facing ALB."
  type        = list(string)
}

variable "private_app_subnet_cidrs" {
  description = "Private app subnet CIDR blocks for EKS worker nodes and pods."
  type        = list(string)
}

variable "karpenter_node_subnet_cidrs" {
  description = "Private subnet CIDR blocks for Karpenter nodes, one per availability zone. Empty list creates none."
  type        = list(string)
  default     = []
}

variable "private_data_subnet_cidrs" {
  description = "Private data subnet CIDR blocks for RDS, Redis, OpenSearch, and reserved data subnet."
  type        = list(string)
}

variable "tgw_subnet_cidrs" {
  description = "TGW attachment subnet CIDR blocks."
  type        = list(string)
}

variable "transit_gateway_id" {
  description = "Transit Gateway ID. If null, TGW routes are not created yet."
  type        = string
  default     = null
}

variable "tags" {
  description = "Common tags."
  type        = map(string)
  default     = {}
}

variable "eks_cluster_name" {
  description = "EKS cluster name used for Kubernetes subnet discovery tags."
  type        = string
  default     = ""
}

