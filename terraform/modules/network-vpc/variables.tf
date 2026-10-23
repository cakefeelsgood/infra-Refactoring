variable "project_name" {
  description = "Project name."
  type        = string
}

variable "env" {
  description = "Environment name."
  type        = string
}


variable "enable_nat_gateway" {
  description = "Whether to create Network VPC NAT Gateways and their EIPs/routes."
  type        = bool
  default     = true
}

variable "vpc_cidr" {
  description = "Network VPC CIDR block."
  type        = string
}

variable "availability_zones" {
  description = "Availability zones for subnet creation."
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) > 0
    error_message = "availability_zones must contain at least one Availability Zone."
  }
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDR blocks."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_cidrs) > 0
    error_message = "public_subnet_cidrs must contain at least one CIDR block."
  }

  validation {
    condition     = length(var.public_subnet_cidrs) <= length(var.availability_zones)
    error_message = "public_subnet_cidrs count must be less than or equal to availability_zones count."
  }
}

variable "tgw_subnet_cidrs" {
  description = "TGW attachment subnet CIDR blocks."
  type        = list(string)

  validation {
    condition     = length(var.tgw_subnet_cidrs) > 0
    error_message = "tgw_subnet_cidrs must contain at least one CIDR block."
  }

  validation {
    condition     = length(var.tgw_subnet_cidrs) == length(var.public_subnet_cidrs)
    error_message = "tgw_subnet_cidrs count must match public_subnet_cidrs count so each TGW subnet can route to the NAT Gateway in the same AZ."
  }

  validation {
    condition     = length(var.tgw_subnet_cidrs) <= length(var.availability_zones)
    error_message = "tgw_subnet_cidrs count must be less than or equal to availability_zones count."
  }
}

variable "tags" {
  description = "Common tags."
  type        = map(string)
  default     = {}
}
