variable "name_prefix" {
  description = "Name prefix for OpenVPN resources."
  type        = string
}

variable "environment" {
  description = "Environment name for OpenVPN resources."
  type        = string
}

variable "subnet_id" {
  description = "Network VPC public subnet ID where OpenVPN EC2 is placed."
  type        = string
}

variable "security_group_id" {
  description = "OpenVPN security group ID."
  type        = string
}

variable "ami_id" {
  description = "Optional AMI ID. If empty, the latest Amazon Linux 2023 x86_64 AMI is selected."
  type        = string
  default     = ""
}

variable "instance_type" {
  description = "OpenVPN EC2 instance type."
  type        = string
  default     = "t3.micro"
}

variable "associate_public_ip_address" {
  description = "Whether to associate a public IP address with the OpenVPN instance."
  type        = bool
  default     = true
}

variable "enable_eip" {
  description = "Whether to allocate and associate an Elastic IP for stable OpenVPN endpoint."
  type        = bool
  default     = true
}

variable "root_volume_size" {
  description = "OpenVPN EC2 root volume size in GiB."
  type        = number
  default     = 8
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

variable "vpn_cidr" {
  description = "OpenVPN client tunnel CIDR."
  type        = string
  default     = "10.8.0.0/24"
}

variable "route_cidrs" {
  description = "CIDR blocks pushed to OpenVPN clients."
  type        = list(string)
}

variable "enable_masquerade" {
  description = "Whether to MASQUERADE VPN client traffic toward pushed route CIDRs. Keep false for routed VPN so Data Tier can see the VPN client CIDR."
  type        = bool
  default     = false
}

variable "client_name" {
  description = "Default OpenVPN client profile name generated on the instance."
  type        = string
  default     = "moment-admin"
}

variable "client_profile_secret_name" {
  description = "Secrets Manager secret name for generated OpenVPN client profile. If empty, a project-based default name is used."
  type        = string
  default     = ""
}


variable "client_profile_secret_arn" {
  description = "ARN of the externally managed Secrets Manager secret where the generated OpenVPN client profile is stored."
  type        = string
}

variable "client_profile_secret_recovery_window_in_days" {
  description = "Secrets Manager recovery window in days. Use 0 for short-lived validation environments."
  type        = number
  default     = 0
}

variable "common_tags" {
  description = "Common tags applied to OpenVPN resources."
  type        = map(string)
  default     = {}
}
