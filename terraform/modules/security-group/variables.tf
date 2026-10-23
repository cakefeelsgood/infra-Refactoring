variable "name_prefix" {
  description = "Name prefix for security groups"
  type        = string
}

variable "environment" {
  description = "Environment name such as prod, dev, network"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where security groups will be created"
  type        = string
}

variable "create_service_sg" {
  description = "Whether to create service security groups such as ALB, EKS, RDS, Redis, OpenSearch and VPC Endpoint"
  type        = bool
  default     = true
}

variable "create_openvpn_sg" {
  description = "Whether to create OpenVPN security group"
  type        = bool
  default     = false
}

variable "use_cloudfront_prefix_list" {
  description = "Whether ALB ingress uses AWS managed CloudFront origin-facing prefix list"
  type        = bool
  default     = true
}

variable "alb_allowed_cidr_blocks" {
  description = "Additional CIDR blocks allowed to access ALB HTTPS. Keep empty when using only CloudFront prefix list."
  type        = list(string)
  default     = []
}

variable "admin_cidr_blocks" {
  description = "Administrator CIDR blocks allowed to access OpenVPN"
  type        = list(string)
  default     = []
}

variable "openvpn_client_cidr_blocks" {
  description = "OpenVPN client CIDR blocks allowed to access Data Tier services with explicit ports."
  type        = list(string)
  default     = []
}

variable "app_port" {
  description = "Application port exposed by EKS workload"
  type        = number
  default     = 8080
}

variable "openvpn_port" {
  description = "OpenVPN port"
  type        = number
  default     = 1194
}

variable "openvpn_protocol" {
  description = "OpenVPN protocol"
  type        = string
  default     = "udp"
}




variable "common_tags" {
  description = "Common tags applied to all security groups"
  type        = map(string)
  default     = {}
}
