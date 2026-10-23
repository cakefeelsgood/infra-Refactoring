variable "project_name" {
  description = "Project name."
  type        = string
}

variable "env" {
  description = "Workload environment name. Example: prod."
  type        = string
}

variable "vpc_cidr" {
  description = "Prod VPC CIDR block."
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
  description = "Private data subnet CIDR blocks for RDS, Redis, and OpenSearch."
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

variable "private_app_default_route_target" {
  description = "Default egress target for Prod private app subnets. Use nat for local NAT Gateway egress or tgw for centralized TGW egress."
  type        = string
  default     = "nat"

  validation {
    condition     = contains(["nat", "tgw"], var.private_app_default_route_target)
    error_message = "private_app_default_route_target must be either nat or tgw."
  }
}

variable "enable_private_app_to_network_vpc_route" {
  description = "Whether this module manages the Prod private app route to the Network VPC CIDR. Keep false when the Network environment already owns this route."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags."
  type        = map(string)
  default     = {}
}

variable "eks_cluster_name" {
  description = "EKS cluster name used for Kubernetes subnet discovery tags. When null, cluster discovery tags are not added."
  type        = string
  default     = null
}
