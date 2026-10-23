variable "project_name" {
  description = "Project name."
  type        = string
}

variable "env" {
  description = "Terraform environment name."
  type        = string
}

variable "network_vpc_id" {
  description = "Network VPC ID."
  type        = string
}

variable "network_vpc_cidr" {
  description = "Network VPC CIDR block."
  type        = string
}

variable "network_tgw_subnet_ids" {
  description = "Network VPC TGW attachment subnet IDs."
  type        = list(string)
}

variable "network_public_route_table_id" {
  description = "Network VPC public route table ID. NAT Gateway public subnet uses this route table."
  type        = string
}

variable "openvpn_vpn_cidr" {
  description = "OpenVPN client tunnel CIDR that should route back to the Network VPC attachment."
  type        = string
  default     = "10.8.0.0/24"
}

variable "enable_openvpn_client_routes" {
  description = "Whether to create TGW and VPC routes for routed OpenVPN client CIDR."
  type        = bool
  default     = false
}

variable "prod_vpc_id" {
  description = "Prod VPC ID."
  type        = string
}

variable "prod_vpc_cidr" {
  description = "Prod VPC CIDR block."
  type        = string
}

variable "prod_tgw_subnet_ids" {
  description = "Prod VPC TGW attachment subnet IDs."
  type        = list(string)
}

variable "prod_private_app_route_table_id" {
  description = "Prod VPC private app route table ID."
  type        = string
}

variable "prod_private_data_route_table_id" {
  description = "Prod VPC private data route table ID. Used for OpenVPN client CIDR return route."
  type        = string
  default     = ""
}

variable "dev_vpc_id" {
  description = "Dev VPC ID."
  type        = string
}

variable "dev_vpc_cidr" {
  description = "Dev VPC CIDR block."
  type        = string
}

variable "dev_tgw_subnet_ids" {
  description = "Dev VPC TGW attachment subnet IDs."
  type        = list(string)
}

variable "dev_private_app_route_table_id" {
  description = "Dev VPC private app route table ID."
  type        = string
}

variable "dev_private_data_route_table_id" {
  description = "Dev VPC private data route table ID. Used for OpenVPN client CIDR return route."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Common tags."
  type        = map(string)
  default     = {}
}

variable "enable_dev_private_app_default_to_tgw" {
  description = "Whether the Transit Gateway module manages Dev private app 0.0.0.0/0 route. Disable when Dev environment owns default egress through its own NAT Gateway."
  type        = bool
  default     = true
}

variable "enable_prod_private_app_default_to_tgw" {
  description = "Whether the Transit Gateway module manages Prod private app 0.0.0.0/0 route. Disable during Network/TGW bootstrap when Prod still owns default egress through its legacy NAT Gateway."
  type        = bool
  default     = true
}
