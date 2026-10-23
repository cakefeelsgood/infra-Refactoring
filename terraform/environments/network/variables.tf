variable "project_name" {
  description = "Project name."
  type        = string
  default     = "moment"
}

variable "env" {
  description = "Terraform environment name."
  type        = string
  default     = "network"
}

variable "primary_region" {
  description = "Primary AWS region."
  type        = string
  default     = "ap-northeast-3"
}

variable "enable_network_vpc" {
  description = "Whether to create Network VPC resources from this environment. Keep false until migration is approved."
  type        = bool
  default     = false
}


variable "enable_network_nat_gateway" {
  description = "Whether to create Network VPC centralized NAT Gateways. Set false for NAT-only costdown while preserving Network VPC and TGW."
  type        = bool
  default     = true
}

variable "enable_transit_gateway" {
  description = "Whether to create Transit Gateway resources from this environment. Keep false until migration is approved."
  type        = bool
  default     = false
}

variable "enable_openvpn" {
  description = "Whether to create OpenVPN resources from this environment. Keep false until migration is approved."
  type        = bool
  default     = false
}

variable "network_vpc_cidr" {
  description = "Network VPC CIDR block."
  type        = string
  default     = "10.0.0.0/16"
}

variable "prod_vpc_cidr" {
  description = "Prod VPC CIDR block."
  type        = string
  default     = "10.10.0.0/16"
}

variable "dev_vpc_cidr" {
  description = "Dev VPC CIDR block."
  type        = string
  default     = "10.20.0.0/16"
}

variable "network_public_subnet_cidrs" {
  description = "Network VPC public subnet CIDRs."
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "network_tgw_subnet_cidrs" {
  description = "Network VPC TGW subnet CIDRs."
  type        = list(string)
  default     = ["10.0.100.0/28", "10.0.100.16/28"]
}

variable "prod_vpc_id" {
  description = "Prod VPC ID supplied from prod environment."
  type        = string
  default     = ""
}

variable "prod_tgw_subnet_ids" {
  description = "Prod TGW subnet IDs supplied from prod environment."
  type        = list(string)
  default     = []
}

variable "prod_private_app_route_table_id" {
  description = "Prod private app route table ID supplied from prod environment."
  type        = string
  default     = ""
}

variable "prod_private_data_route_table_id" {
  description = "Prod VPC private data route table ID for OpenVPN client CIDR return route."
  type        = string
  default     = ""
}

variable "dev_vpc_id" {
  description = "Dev VPC ID supplied from dev environment."
  type        = string
  default     = ""
}

variable "dev_tgw_subnet_ids" {
  description = "Dev TGW subnet IDs supplied from dev environment."
  type        = list(string)
  default     = []
}

variable "dev_private_app_route_table_id" {
  description = "Dev private app route table ID supplied from dev environment."
  type        = string
  default     = ""
}

variable "dev_private_data_route_table_id" {
  description = "Dev VPC private data route table ID for OpenVPN client CIDR return route."
  type        = string
  default     = ""
}

variable "admin_cidr_blocks" {
  description = "Administrator CIDR blocks allowed to access OpenVPN."
  type        = list(string)
  default     = []
}

variable "openvpn_ami_id" {
  description = "Optional OpenVPN AMI ID. If empty, the module selects the latest Amazon Linux 2023 AMI."
  type        = string
  default     = ""
}

variable "openvpn_instance_type" {
  description = "OpenVPN EC2 instance type."
  type        = string
  default     = "t3.micro"
}

variable "openvpn_enable_eip" {
  description = "Whether to allocate Elastic IP for OpenVPN."
  type        = bool
  default     = true
}

variable "openvpn_port" {
  description = "OpenVPN UDP port."
  type        = number
  default     = 1194
}

variable "openvpn_protocol" {
  description = "OpenVPN protocol."
  type        = string
  default     = "udp"
}

variable "openvpn_vpn_cidr" {
  description = "OpenVPN client tunnel CIDR."
  type        = string
  default     = "10.8.0.0/24"
}

variable "openvpn_enable_masquerade" {
  description = "Whether OpenVPN should MASQUERADE VPN client traffic to Dev/Prod CIDRs. Keep false for routed VPN Data Tier admin access."
  type        = bool
  default     = false
}

variable "openvpn_client_name" {
  description = "OpenVPN client profile name."
  type        = string
  default     = "moment-admin"
}


variable "preserve_openvpn_client_profile_secret" {
  description = "Whether to keep the OpenVPN client profile secret even when OpenVPN/Network runtime resources are disabled for cost-down."
  type        = bool
  default     = true
}

variable "openvpn_client_profile_secret_name" {
  description = "Secrets Manager secret name for generated OpenVPN client profile."
  type        = string
  default     = ""
}

variable "openvpn_client_profile_secret_recovery_window_in_days" {
  description = "Secrets Manager recovery window in days."
  type        = number
  default     = 0
}

variable "openvpn_root_volume_size" {
  description = "OpenVPN EC2 root volume size in GiB."
  type        = number
  default     = 8
}

variable "enable_dev_private_app_default_to_tgw" {
  description = "Whether Network environment should manage Dev private app default route to TGW. Keep false when Dev owns 0.0.0.0/0 through Dev NAT."
  type        = bool
  default     = false
}

variable "enable_prod_private_app_default_to_tgw" {
  description = "Whether Network environment should manage Prod private app default route to TGW. Keep false during Network/TGW bootstrap while Prod still owns 0.0.0.0/0 through legacy Prod NAT."
  type        = bool
  default     = false
}
