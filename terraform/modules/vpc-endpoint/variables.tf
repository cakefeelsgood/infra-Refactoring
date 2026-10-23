variable "name_prefix" {
  description = "Name prefix for VPC endpoints"
  type        = string
}

variable "environment" {
  description = "Environment name such as prod or dev"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where endpoints will be created"
  type        = string
}

variable "private_app_subnet_ids" {
  description = "Private App subnet IDs for Interface Endpoints"
  type        = list(string)
}

variable "private_app_route_table_ids" {
  description = "Private App route table IDs for S3 Gateway Endpoint"
  type        = list(string)
}

variable "endpoint_security_group_id" {
  description = "Security group ID attached to Interface Endpoints"
  type        = string
}

variable "common_tags" {
  description = "Common tags applied to endpoints"
  type        = map(string)
  default     = {}
}