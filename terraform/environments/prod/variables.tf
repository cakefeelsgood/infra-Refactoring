variable "project_name" {
  description = "Project name used for resource naming and tagging."
  type        = string
  default     = "moment"
}

variable "env" {
  description = "Environment name."
  type        = string
  default     = "prod"
}

variable "primary_region" {
  description = "Primary AWS region."
  type        = string
  default     = "ap-northeast-3"
}

variable "network_vpc_cidr" {
  description = "CIDR block for Network VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "prod_vpc_cidr" {
  description = "CIDR block for Prod VPC."
  type        = string
  default     = "10.10.0.0/16"
}

variable "dev_vpc_cidr" {
  description = "CIDR block for Dev VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "admin_cidr_blocks" {
  description = "Administrator CIDR blocks allowed to access internal resources when explicit admin access rules are added."
  type        = list(string)
  default     = []
}

variable "openvpn_vpn_cidr" {
  description = "OpenVPN client tunnel CIDR used for routed admin access to Data Tier."
  type        = string
  default     = "10.8.0.0/24"
}

variable "app_port" {
  description = "Application port exposed by EKS workload."
  type        = number
  default     = 8080
}

variable "prod_transit_gateway_id" {
  description = "Existing Transit Gateway ID for Prod VPC routes. Keep null until shared/network state handoff is defined."
  type        = string
  default     = null
}

variable "prod_private_app_default_route_target" {
  description = "Default egress target for Prod private app subnets. Keep nat unless centralized TGW egress has been explicitly validated."
  type        = string
  default     = "nat"

  validation {
    condition     = contains(["nat", "tgw"], var.prod_private_app_default_route_target)
    error_message = "prod_private_app_default_route_target must be either nat or tgw."
  }
}

variable "enable_prod_ecr" {
  description = "Whether to create Prod ECR repositories. Disabled by default for cost saving and migration safety."
  type        = bool
  default     = false
}

variable "enable_prod_vpc" {
  description = "Whether to preserve/manage existing Prod VPC foundation resources in terraform/environments/prod."
  type        = bool
  default     = true
}

variable "enable_prod_vpc_endpoints" {
  description = "Whether to create Prod VPC endpoints."
  type        = bool
  default     = false
}

variable "enable_prod_eks" {
  description = "Whether to create the Prod EKS cluster."
  type        = bool
  default     = false
}

variable "enable_prod_nodegroups" {
  description = "Whether Prod EKS managed node groups are enabled. Detailed Prod nodegroup implementation is handled by M2-EKS-04."
  type        = bool
  default     = false
}

variable "enable_prod_data_tier" {
  description = "Whether Prod data tier resources can be created. Individual RDS/Redis/OpenSearch flags must also be enabled."
  type        = bool
  default     = false
}

variable "enable_prod_rds" {
  description = "Whether to create Prod RDS PostgreSQL."
  type        = bool
  default     = false
}

variable "enable_prod_rds_read_replica" {
  description = "Whether to create a Prod RDS read replica. Disabled by default and reserved for future scaling."
  type        = bool
  default     = false
}

variable "enable_prod_redis" {
  description = "Whether to create Prod ElastiCache Redis."
  type        = bool
  default     = false
}

variable "enable_prod_opensearch" {
  description = "Whether to create Prod OpenSearch."
  type        = bool
  default     = false
}

variable "enable_prod_sqs" {
  description = "Whether to create Prod SQS queues."
  type        = bool
  default     = false
}

variable "enable_prod_external_secrets_irsa" {
  description = "Whether to create Prod External Secrets Operator IRSA role and runtime secret containers."
  type        = bool
  default     = false
}

variable "prod_external_secrets_namespace" {
  description = "Namespace where External Secrets Operator is installed in Prod EKS."
  type        = string
  default     = "external-secrets"
}

variable "prod_external_secrets_service_account_name" {
  description = "ServiceAccount name used by External Secrets Operator in Prod EKS."
  type        = string
  default     = "external-secrets"
}

variable "enable_prod_s3_raw_bucket" {
  description = "Whether to manage Prod S3 Raw Bucket in terraform/environments/prod. Keep false until Prod data pipeline activation is approved."
  type        = bool
  default     = false
}

variable "prod_raw_bucket_name" {
  description = "Optional explicit Prod S3 Raw Bucket name. Keep null to use the module naming convention."
  type        = string
  default     = null
}

variable "enable_prod_profile_image_bucket" {
  description = "Whether to manage Prod profile image upload S3 bucket. Keep false until Prod activation is approved."
  type        = bool
  default     = false
}

variable "prod_profile_image_bucket_name" {
  description = "Optional explicit Prod profile image S3 bucket name. Keep null to use the module naming convention."
  type        = string
  default     = null
}

variable "prod_profile_image_allowed_origins" {
  description = "Allowed CORS origins for Prod profile image Presigned PUT upload."
  type        = list(string)
  default     = []
}

variable "prod_profile_image_object_key_prefix" {
  description = "S3 object key prefix used by Backend profile image upload in Prod."
  type        = string
  default     = "uploads/profile"
}


variable "enable_prod_notification_sns" {
  description = "Whether to manage Prod notification SNS topic. Keep false until Prod activation is approved."
  type        = bool
  default     = false
}

variable "prod_notification_sns_topic_name" {
  description = "Optional explicit Prod notification SNS topic name. Keep null to use the module naming convention."
  type        = string
  default     = null
}

variable "prod_notification_sns_display_name" {
  description = "Prod notification SNS topic display name."
  type        = string
  default     = "MoMent Prod Notification"
}

variable "prod_notification_sns_kms_master_key_id" {
  description = "Optional KMS key ID or alias for Prod notification SNS topic encryption. Keep null unless KMS encryption is explicitly required."
  type        = string
  default     = null
}


variable "enable_prod_data_pipeline" {
  description = "Whether to create Prod EventBridge Scheduler and Lambda Collector."
  type        = bool
  default     = false
}

variable "enable_edge" {
  description = "Whether to preserve/manage existing Prod Edge resources already tracked in terraform/environments/prod."
  type        = bool
  default     = true
}

variable "shared_lambda_collector_role_arn" {
  description = "Shared Lambda Collector IAM role ARN. Prod data pipeline uses shared IAM instead of duplicating account-level IAM."
  type        = string
  default     = ""
}

variable "prod_eks_cluster_name" {
  description = "Prod EKS cluster name."
  type        = string
  default     = "moment-prod-eks-cluster"
}

variable "prod_eks_kubernetes_version" {
  description = "Kubernetes version for Prod EKS cluster."
  type        = string
  default     = "1.35"
}

variable "prod_eks_cluster_role_arn" {
  description = "Existing shared IAM role ARN for the EKS control plane. Required only when enable_prod_eks is true."
  type        = string
  default     = ""
}

variable "prod_eks_node_role_arn" {
  description = "Existing shared IAM role ARN for Prod EKS node groups. Reserved for M2-EKS-04."
  type        = string
  default     = ""
}

variable "prod_eks_public_access_cidrs" {
  description = "CIDR blocks allowed to access the Prod EKS public API endpoint when Prod EKS is enabled."
  type        = list(string)
  default     = []
}

variable "prod_eks_cluster_admin_principal_arn" {
  description = "Primary IAM principal ARN granted cluster-admin access through EKS Access Entry."
  type        = string
  default     = ""
}

variable "prod_eks_cluster_admin_additional_principal_arns" {
  description = "Additional IAM principal ARNs granted cluster-admin access through EKS Access Entry."
  type        = set(string)
  default     = []
}

variable "prod_sqs_visibility_timeout_seconds" {
  description = "Prod SQS visibility timeout in seconds for public data Batch processing."
  type        = number
  default     = 900
}

variable "prod_sqs_message_retention_seconds" {
  description = "Prod SQS main queue message retention in seconds for operational replay and failure analysis."
  type        = number
  default     = 604800
}

variable "prod_sqs_dlq_message_retention_seconds" {
  description = "Prod SQS DLQ message retention in seconds for incident evidence and reprocessing."
  type        = number
  default     = 1209600
}

variable "prod_sqs_max_receive_count" {
  description = "Prod SQS receive attempts before moving a message to the DLQ."
  type        = number
  default     = 5
}

variable "prod_sqs_receive_wait_time_seconds" {
  description = "Prod SQS long polling wait time in seconds."
  type        = number
  default     = 20
}

variable "prod_sqs_delay_seconds" {
  description = "Prod SQS delay for new messages in seconds."
  type        = number
  default     = 0
}

variable "prod_sqs_max_message_size" {
  description = "Prod SQS maximum message size in bytes."
  type        = number
  default     = 262144
}

variable "prod_sqs_managed_sse_enabled" {
  description = "Whether Prod SQS managed server-side encryption is enabled."
  type        = bool
  default     = true
}

variable "data_pipeline_public_data_api_url" {
  description = "Legacy single Public Data API URL. Prefer data_pipeline_public_data_sources_json or secret name."
  type        = string
  default     = ""
}

variable "data_pipeline_public_data_sources_json" {
  description = "Legacy inline JSON array of public data source configs. Prefer data_pipeline_public_data_sources_secret_name."
  type        = string
  default     = "[]"

  validation {
    condition     = can(jsondecode(var.data_pipeline_public_data_sources_json))
    error_message = "data_pipeline_public_data_sources_json must be valid JSON."
  }
}

variable "data_pipeline_public_data_sources_secret_name" {
  description = "Secrets Manager secret name containing public data source configs."
  type        = string
  default     = ""
}

variable "data_pipeline_schedule_expression" {
  description = "EventBridge Scheduler expression for public data collection."
  type        = string
  default     = "rate(1 day)"
}

variable "prod_data_pipeline_schedule_state" {
  description = "Prod EventBridge Scheduler state. Keep DISABLED outside final demo or rehearsal."
  type        = string
  default     = "DISABLED"
}

variable "data_pipeline_lambda_runtime" {
  description = "Lambda Collector runtime."
  type        = string
  default     = "python3.12"
}

variable "data_pipeline_lambda_timeout" {
  description = "Lambda Collector timeout in seconds."
  type        = number
  default     = 30
}

variable "data_pipeline_lambda_memory_size" {
  description = "Lambda Collector memory size in MB."
  type        = number
  default     = 128
}

variable "data_pipeline_log_retention_days" {
  description = "CloudWatch Logs retention days for Lambda Collector."
  type        = number
  default     = 14
}

variable "redis_engine_version" {
  description = "Redis engine version."
  type        = string
  default     = "7.0"
}

variable "prod_redis_node_type" {
  description = "Prod Redis node type."
  type        = string
  default     = "cache.t3.small"
}

variable "prod_redis_num_cache_clusters" {
  description = "Number of cache clusters for Prod Redis HA. Primary 1 + Replica 1 = 2."
  type        = number
  default     = 2
}

variable "prod_redis_multi_az_enabled" {
  description = "Enable Multi-AZ for the Prod Redis replication group. Prod backup/restore and HA baseline requires this to be true."
  type        = bool
  default     = true

  validation {
    condition     = var.prod_redis_multi_az_enabled == true
    error_message = "prod_redis_multi_az_enabled must be true for Prod data-tier HA and recovery readiness."
  }
}

variable "prod_redis_snapshot_retention_limit" {
  description = "Number of days to retain automatic Redis snapshots in Prod. Must be at least 3 for the MoMent Prod backup baseline."
  type        = number
  default     = 3

  validation {
    condition     = var.prod_redis_snapshot_retention_limit >= 3
    error_message = "prod_redis_snapshot_retention_limit must be greater than or equal to 3 for Prod backup readiness."
  }
}

variable "prod_redis_automatic_failover_enabled" {
  description = "Enable automatic failover for the Prod Redis replication group. Prod HA baseline requires this to be true."
  type        = bool
  default     = true

  validation {
    condition     = var.prod_redis_automatic_failover_enabled == true
    error_message = "prod_redis_automatic_failover_enabled must be true for Prod Redis HA and recovery readiness."
  }
}

variable "rds_engine_version" {
  description = "PostgreSQL engine version for RDS."
  type        = string
  default     = "17.10"
}

variable "rds_parameter_group_family" {
  description = "PostgreSQL parameter group family for RDS."
  type        = string
  default     = "postgres17"
}

variable "rds_database_name" {
  description = "Initial PostgreSQL database name."
  type        = string
  default     = "moment"
}

variable "rds_master_username" {
  description = "PostgreSQL master username."
  type        = string
  default     = "moment_admin"
}

variable "prod_rds_instance_class" {
  description = "Prod RDS instance class."
  type        = string
  default     = "db.t4g.small"
}

variable "prod_rds_allocated_storage" {
  description = "Allocated Prod RDS storage size in GiB."
  type        = number
  default     = 50
}

variable "prod_rds_max_allocated_storage" {
  description = "Maximum Prod RDS storage size in GiB for autoscaling."
  type        = number
  default     = 200
}

variable "prod_rds_multi_az" {
  description = "Whether Prod RDS PostgreSQL uses Multi-AZ Primary/Standby deployment."
  type        = bool
  default     = true
}

variable "prod_rds_backup_retention_period" {
  description = "Backup retention period in days for Prod RDS PostgreSQL."
  type        = number
  default     = 14
}

variable "prod_rds_backup_window" {
  description = "Preferred backup window for Prod RDS PostgreSQL."
  type        = string
  default     = "18:00-19:00"
}

variable "prod_rds_maintenance_window" {
  description = "Preferred maintenance window for Prod RDS PostgreSQL."
  type        = string
  default     = "sun:19:00-sun:20:00"
}

variable "prod_rds_deletion_protection" {
  description = "Enable deletion protection for the Prod RDS instance. Prod backup/restore baseline requires this to be true."
  type        = bool
  default     = true

  validation {
    condition     = var.prod_rds_deletion_protection == true
    error_message = "prod_rds_deletion_protection must be true for Prod RDS protection."
  }
}

variable "prod_rds_skip_final_snapshot" {
  description = "Whether to skip final snapshot on Prod RDS deletion. Prod backup/restore baseline requires this to be false."
  type        = bool
  default     = false

  validation {
    condition     = var.prod_rds_skip_final_snapshot == false
    error_message = "prod_rds_skip_final_snapshot must be false so Prod RDS keeps a final snapshot before deletion."
  }
}

variable "prod_rds_final_snapshot_identifier" {
  description = "Final snapshot identifier for Prod RDS. If null, a default project-based name is used."
  type        = string
  default     = null
}

variable "create_opensearch_service_linked_role" {
  description = "Whether to create the account-level OpenSearch service-linked role. Keep false unless the role does not already exist."
  type        = bool
  default     = false
}

variable "opensearch_engine_version" {
  description = "OpenSearch engine version."
  type        = string
  default     = "OpenSearch_2.17"
}

variable "prod_opensearch_instance_type" {
  description = "Prod OpenSearch data node instance type."
  type        = string
  default     = "t3.medium.search"
}

variable "prod_opensearch_instance_count" {
  description = "Number of Prod OpenSearch data nodes."
  type        = number
  default     = 2

  validation {
    condition     = var.prod_opensearch_instance_count >= 2
    error_message = "prod_opensearch_instance_count must be greater than or equal to 2 for Prod zone-aware configuration."
  }
}

variable "prod_opensearch_dedicated_master_enabled" {
  description = "Whether Prod OpenSearch dedicated master nodes are enabled."
  type        = bool
  default     = true
}

variable "prod_opensearch_dedicated_master_type" {
  description = "Prod OpenSearch dedicated master node instance type."
  type        = string
  default     = "t3.small.search"
}

variable "prod_opensearch_dedicated_master_count" {
  description = "Number of Prod OpenSearch dedicated master nodes."
  type        = number
  default     = 3

  validation {
    condition     = contains([3, 5], var.prod_opensearch_dedicated_master_count)
    error_message = "prod_opensearch_dedicated_master_count must be 3 or 5."
  }
}

variable "prod_opensearch_zone_awareness_enabled" {
  description = "Whether Prod OpenSearch uses zone awareness."
  type        = bool
  default     = true
}

variable "prod_opensearch_availability_zone_count" {
  description = "Availability zone count for Prod OpenSearch zone awareness."
  type        = number
  default     = 2

  validation {
    condition     = contains([2, 3], var.prod_opensearch_availability_zone_count)
    error_message = "prod_opensearch_availability_zone_count must be 2 or 3."
  }
}

variable "prod_opensearch_multi_az_with_standby_enabled" {
  description = "Whether Prod OpenSearch Multi-AZ with Standby is enabled. Keep false for the current 2-AZ Prod VPC design."
  type        = bool
  default     = false
}

variable "opensearch_ebs_volume_type" {
  description = "OpenSearch EBS volume type."
  type        = string
  default     = "gp3"
}

variable "prod_opensearch_ebs_volume_size" {
  description = "Prod OpenSearch EBS volume size in GiB."
  type        = number
  default     = 50

  validation {
    condition     = var.prod_opensearch_ebs_volume_size >= 20
    error_message = "prod_opensearch_ebs_volume_size must be greater than or equal to 20 GiB."
  }
}

variable "enable_waf" {
  description = "Whether to create WAF Web ACL."
  type        = bool
  default     = true
}

variable "edge_domain_name" {
  description = "Custom domain name. Empty string uses CloudFront default domain."
  type        = string
  default     = ""
}

variable "edge_hosted_zone_name" {
  description = "Route53 Hosted Zone 이름. 예: moment-team04.click"
  type        = string
  default     = ""
}

variable "edge_subject_alternative_names" {
  description = "ACM subject alternative names."
  type        = list(string)
  default     = []
}

variable "create_route53_hosted_zone" {
  description = "Whether to create a new Route53 Hosted Zone."
  type        = bool
  default     = false
}

variable "prod_alb_dns_name" {
  description = "Prod ALB DNS name used as CloudFront origin. Keep empty until Prod ALB is ready."
  type        = string
  default     = ""
}

variable "prod_alb_https_enabled" {
  description = "Whether CloudFront to Prod ALB uses HTTPS."
  type        = bool
  default     = false
}

variable "cloudfront_secret_header_value" {
  description = "X-CloudFront-Secret header value for ALB direct access restriction."
  type        = string
  sensitive   = true
  default     = "moment-cf-secret-change-me"
}

variable "cloudfront_price_class" {
  description = "CloudFront price class."
  type        = string
  default     = "PriceClass_All"
}

variable "enable_prod_iam" {
  description = "Whether to manage Prod environment IAM roles and policies from terraform/environments/prod. Keep false until Prod IAM activation is approved."
  type        = bool
  default     = false
}

variable "github_repository" {
  description = "GitHub repository allowed to assume GitHub Actions role."
  type        = string
  default     = "Team-msp-architect-2026/msp-team04-infra"
}

variable "github_default_branch" {
  description = "Default branch allowed to assume GitHub Actions role."
  type        = string
  default     = "develop"
}

variable "github_oidc_allowed_subjects" {
  description = "GitHub OIDC sub conditions allowed to assume the GitHub Actions role."
  type        = list(string)
  default = [
    "repo:Team-msp-architect-2026/msp-team04-infra:ref:refs/heads/develop"
  ]
}

variable "github_oidc_provider_arn" {
  description = "Existing account-level GitHub Actions OIDC Provider ARN."
  type        = string
  default     = "arn:aws:iam::611058323802:oidc-provider/token.actions.githubusercontent.com"
}

variable "enable_prod_public_data_secrets" {
  description = "Whether to keep Prod public data Secrets Manager secret containers for Lambda Collector. Secret values are managed out-of-band."
  type        = bool
  default     = true
}

variable "enable_lambda_collector_secrets_manager_read" {
  description = "Whether Prod Lambda Collector can read public data API keys from Secrets Manager."
  type        = bool
  default     = false
}


variable "prod_profile_image_public_read_enabled" {
  description = "Whether Prod profile image objects are publicly readable with s3:GetObject. Prefer CloudFront/OAC before enabling in production."
  type        = bool
  default     = false
}


variable "enable_prod_workload_irsa" {
  description = "Whether to create Prod workload IRSA roles after Prod EKS OIDC provider is available."
  type        = bool
  default     = false
}


variable "enable_prod_alerting_slack_notifier" {
  description = "Whether to create Prod CloudWatch alert SNS topic and Slack notifier Lambda."
  type        = bool
  default     = true
}

variable "enable_prod_cloudwatch_alarms" {
  description = "Whether to create Prod CloudWatch metric alarms for Terraform-managed AWS resources."
  type        = bool
  default     = true
}

variable "prod_alerting_slack_webhook_secret_name" {
  description = "Secrets Manager secret name for Prod monitoring Slack webhook. Secret value is managed out-of-band."
  type        = string
  default     = "moment/prod/monitoring/slack-alert-webhook"
}

variable "prod_alerting_sns_topic_name" {
  description = "Optional explicit Prod monitoring alert SNS topic name."
  type        = string
  default     = null
}

variable "prod_alerting_application_load_balancer_tag_selectors" {
  description = "Prod AWS Load Balancer Controller managed ALB tag selectors for CloudWatch alarms."
  type = map(object({
    tags = map(string)
  }))
  default = {
    backend_api = {
      tags = {
        "ingress.k8s.aws/resource" = "LoadBalancer"
        "ingress.k8s.aws/stack"    = "moment-prod/backend-api"
        "elbv2.k8s.aws/cluster"    = "moment-prod-eks-cluster"
      }
    }
  }
}

variable "prod_alerting_target_group_tag_selectors" {
  description = "Prod AWS Load Balancer Controller managed Target Group tag selectors for CloudWatch alarms."
  type = map(object({
    load_balancer_key = string
    tags              = map(string)
  }))
  default = {
    backend_api = {
      load_balancer_key = "backend_api"
      tags = {
        "ingress.k8s.aws/resource" = "moment-prod/backend-api-backend-api:8080"
        "ingress.k8s.aws/stack"    = "moment-prod/backend-api"
        "elbv2.k8s.aws/cluster"    = "moment-prod-eks-cluster"
      }
    }
  }
}

variable "prod_opensearch_recovery_strategy" {
  description = "Recovery strategy for Prod OpenSearch. MoMent treats OpenSearch as a derived search index and restores it by reindexing from RDS and S3 Raw."
  type        = string
  default     = "reindex_from_rds_s3_raw"

  validation {
    condition     = contains(["reindex_from_rds_s3_raw"], var.prod_opensearch_recovery_strategy)
    error_message = "Only reindex_from_rds_s3_raw is currently supported for Prod OpenSearch recovery."
  }
}

variable "prod_opensearch_source_of_truth" {
  description = "Authoritative source used to rebuild Prod OpenSearch indexes."
  type        = string
  default     = "rds_and_s3_raw"

  validation {
    condition     = contains(["rds_and_s3_raw"], var.prod_opensearch_source_of_truth)
    error_message = "prod_opensearch_source_of_truth must be rds_and_s3_raw for the current MoMent data-tier recovery design."
  }
}

variable "enable_prod_external_dns" {
  description = "Whether to create Prod ExternalDNS IRSA resources for Route53 record automation."
  type        = bool
  default     = false
}

variable "prod_external_dns_namespace" {
  description = "Kubernetes namespace for Prod ExternalDNS."
  type        = string
  default     = "external-dns"
}

variable "prod_external_dns_service_account_name" {
  description = "Kubernetes service account name for Prod ExternalDNS."
  type        = string
  default     = "external-dns"
}

variable "prod_external_dns_hosted_zone_name" {
  description = "Route53 public hosted zone name managed by Prod ExternalDNS."
  type        = string
  default     = "moment-team04.click"
}

variable "prod_external_dns_hosted_zone_id" {
  description = "Route53 public hosted zone ID managed by Prod ExternalDNS. If empty, it is looked up by name."
  type        = string
  default     = ""
}

variable "prod_api_origin_domain_name" {
  description = "Stable Prod API origin domain used by CloudFront. Example: origin-prod-api.moment-team04.click"
  type        = string
  default     = ""
}

variable "enable_prod_karpenter" {
  description = "Whether to create the Prod Karpenter AWS resources (controller IRSA, node role, interruption queue, node subnets)."
  type        = bool
  default     = false
}

variable "prod_karpenter_node_subnet_cidrs" {
  description = "Prod Karpenter node subnet CIDRs, one per AZ (a, c). Sized for VPC CNI Prefix Delegation /28 reservations; must stay inside prod_vpc_cidr and outside the existing subnets."
  type        = list(string)
  default = [
    "10.10.32.0/20",
    "10.10.48.0/20"
  ]
}

variable "enable_prod_legacy_workload_nodegroups" {
  description = "Keep the legacy batch/ai managed node groups. Set false after batch-job/ai-service run on Karpenter NodePools (docs/karpenter.md)."
  type        = bool
  default     = true
}
