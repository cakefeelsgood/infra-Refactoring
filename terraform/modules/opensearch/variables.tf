variable "project_name" {
  description = "Project name used for OpenSearch resource naming."
  type        = string
}

variable "environment" {
  description = "Environment name for OpenSearch resources."
  type        = string
}

variable "domain_name" {
  description = "OpenSearch domain name."
  type        = string
}

variable "engine_version" {
  description = "OpenSearch engine version."
  type        = string
  default     = "OpenSearch_2.17"
}

variable "instance_type" {
  description = "OpenSearch data node instance type."
  type        = string
  default     = "t3.small.search"
}

variable "instance_count" {
  description = "Number of OpenSearch data nodes."
  type        = number
  default     = 1

  validation {
    condition     = var.instance_count >= 1
    error_message = "instance_count must be greater than or equal to 1."
  }
}

variable "dedicated_master_enabled" {
  description = "Whether dedicated master nodes are enabled for OpenSearch cluster stability."
  type        = bool
  default     = false
}

variable "dedicated_master_type" {
  description = "OpenSearch dedicated master node instance type."
  type        = string
  default     = "t3.small.search"
}

variable "dedicated_master_count" {
  description = "Number of OpenSearch dedicated master nodes."
  type        = number
  default     = 3

  validation {
    condition     = contains([3, 5], var.dedicated_master_count)
    error_message = "dedicated_master_count must be 3 or 5."
  }
}

variable "zone_awareness_enabled" {
  description = "Whether OpenSearch zone awareness is enabled."
  type        = bool
  default     = false
}

variable "availability_zone_count" {
  description = "Number of availability zones when zone awareness is enabled."
  type        = number
  default     = 2

  validation {
    condition     = contains([2, 3], var.availability_zone_count)
    error_message = "availability_zone_count must be 2 or 3."
  }
}

variable "multi_az_with_standby_enabled" {
  description = "Whether OpenSearch Multi-AZ with Standby is enabled. Requires 3 AZs and 3 dedicated master nodes."
  type        = bool
  default     = false
}

variable "ebs_volume_type" {
  description = "EBS volume type for OpenSearch data nodes."
  type        = string
  default     = "gp3"
}

variable "ebs_volume_size" {
  description = "EBS volume size in GiB for OpenSearch data nodes."
  type        = number
  default     = 10

  validation {
    condition     = var.ebs_volume_size >= 10
    error_message = "ebs_volume_size must be greater than or equal to 10 GiB."
  }
}

variable "subnet_ids" {
  description = "Private data subnet IDs where OpenSearch VPC endpoints are placed."
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security group IDs attached to OpenSearch."
  type        = list(string)
}

variable "encrypt_at_rest_enabled" {
  description = "Whether encryption at rest is enabled."
  type        = bool
  default     = true
}

variable "node_to_node_encryption_enabled" {
  description = "Whether node-to-node encryption is enabled."
  type        = bool
  default     = true
}

variable "tls_security_policy" {
  description = "TLS security policy for OpenSearch HTTPS endpoint."
  type        = string
  default     = "Policy-Min-TLS-1-2-2019-07"
}

variable "access_policy_principal_type" {
  description = "Principal type used in the OpenSearch access policy."
  type        = string
  default     = "AWS"
}

variable "access_policy_principal_identifiers" {
  description = "Principal identifiers used in the OpenSearch access policy. VPC access is still restricted by subnet and security group."
  type        = list(string)
  default     = ["*"]
}

variable "create_service_linked_role" {
  description = "Whether to create the account-level OpenSearch service-linked role. Enable this only once per AWS account."
  type        = bool
  default     = false
}

variable "common_tags" {
  description = "Common tags applied to OpenSearch resources."
  type        = map(string)
  default     = {}
}
