variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "moment"
}

variable "env" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "primary_region" {
  description = "Primary AWS region"
  type        = string
  default     = "ap-northeast-3"
}

variable "network_vpc_cidr" {
  description = "CIDR block for Network VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "prod_vpc_cidr" {
  description = "CIDR block for Prod VPC"
  type        = string
  default     = "10.10.0.0/16"
}

variable "dev_vpc_cidr" {
  description = "CIDR block for Dev VPC"
  type        = string
  default     = "10.20.0.0/16"
}
variable "admin_cidr_blocks" {
  description = "Administrator CIDR blocks allowed to access OpenVPN"
  type        = list(string)
  default     = []
}

variable "enable_network_openvpn" {
  description = "Whether to create the Network VPC OpenVPN admin access instance."
  type        = bool
  default     = false
}

variable "openvpn_ami_id" {
  description = "Optional AMI ID for OpenVPN. If empty, the OpenVPN module selects the latest Amazon Linux 2023 x86_64 AMI."
  type        = string
  default     = ""
}

variable "openvpn_instance_type" {
  description = "OpenVPN EC2 instance type."
  type        = string
  default     = "t3.micro"
}

variable "openvpn_enable_eip" {
  description = "Whether to allocate an Elastic IP for the OpenVPN instance."
  type        = bool
  default     = true
}

variable "openvpn_port" {
  description = "OpenVPN port."
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

variable "openvpn_client_name" {
  description = "Default OpenVPN client profile name generated on the instance."
  type        = string
  default     = "moment-admin"
}

variable "openvpn_client_profile_secret_name" {
  description = "Secrets Manager secret name for generated OpenVPN client profile. If empty, a project-based default name is used."
  type        = string
  default     = ""
}

variable "openvpn_client_profile_secret_recovery_window_in_days" {
  description = "Secrets Manager recovery window in days for OpenVPN client profile. Use 0 for short-lived validation."
  type        = number
  default     = 0
}

variable "openvpn_root_volume_size" {
  description = "OpenVPN EC2 root volume size in GiB."
  type        = number
  default     = 8
}

variable "app_port" {
  description = "Application port exposed by EKS workload"
  type        = number
  default     = 8080
}

variable "enable_prod_vpc_endpoints" {
  description = "Whether to create Prod VPC Endpoints"
  type        = bool
  default     = false
}

variable "enable_dev_vpc" {
  description = "Whether to create the Dev VPC and VPC-scoped network resources."
  type        = bool
  default     = true
}

variable "enable_dev_vpc_endpoints" {
  description = "Whether to create Dev VPC Endpoints"
  type        = bool
  default     = true
}

variable "enable_dev_eks" {
  description = "Whether to create the Dev EKS cluster by default for practice and validation."
  type        = bool
  default     = true
}

variable "enable_prod_eks" {
  description = "Whether to create the Prod EKS cluster. Disabled by default for cost saving."
  type        = bool
  default     = false
}

variable "dev_eks_cluster_name" {
  description = "Dev EKS cluster name for M2-EKS-01"
  type        = string
  default     = "moment-dev-eks-cluster"
}

variable "dev_eks_public_access_cidrs" {
  description = "CIDR blocks allowed to access the Dev EKS public API endpoint"
  type        = list(string)
  default     = ["115.138.87.55/32"]
}

variable "dev_eks_cluster_admin_principal_arn" {
  description = "IAM principal ARN granted cluster-admin access to the Dev EKS cluster through EKS Access Entry"
  type        = string
  default     = "arn:aws:iam::611058323802:user/student06"
}

variable "enable_dev_eks_cluster_sg_ingress_rules" {
  description = "Whether to create Dev Data Tier ingress rules from the EKS cluster auto-generated security group. Keep true so EKS worker node traffic using the cluster primary security group can reach RDS, Redis, and OpenSearch."
  type        = bool
  default     = true
}

variable "eks_cluster_sg_id" {
  description = "Existing Dev EKS cluster auto-generated security group ID. Set after EKS cluster creation when enabling cluster SG ingress rules."
  type        = string
  default     = ""
}

variable "prod_eks_cluster_name" {
  description = "Prod EKS cluster name for M2-EKS-01. Disabled by default for cost saving."
  type        = string
  default     = "moment-prod-eks-cluster"
}

variable "prod_eks_kubernetes_version" {
  description = "Kubernetes version for Prod EKS cluster"
  type        = string
  default     = "1.35"
}

variable "prod_eks_public_access_cidrs" {
  description = "CIDR blocks allowed to access the Prod EKS public API endpoint when Prod EKS is enabled"
  type        = list(string)
  default     = ["115.138.87.55/32"]
}

variable "prod_eks_cluster_admin_principal_arn" {
  description = "IAM principal ARN granted cluster-admin access through EKS Access Entry"
  type        = string
  default     = "arn:aws:iam::611058323802:user/student06"
}

variable "enable_dev_nodegroups" {
  description = "Whether to create Dev EKS managed node groups."
  type        = bool
  default     = true
}

variable "enable_prod_nodegroups" {
  description = "Whether to create Prod EKS managed node groups. Disabled by default for cost saving."
  type        = bool
  default     = false
}

variable "enable_dev_sqs" {
  description = "Whether to create Dev SQS queues for public data pipeline validation."
  type        = bool
  default     = true
}

variable "dev_sqs_visibility_timeout_seconds" {
  description = "Dev SQS visibility timeout in seconds for public data Batch validation."
  type        = number
  default     = 300
}

variable "dev_sqs_message_retention_seconds" {
  description = "Dev SQS main queue message retention in seconds for short-cycle validation."
  type        = number
  default     = 86400
}

variable "dev_sqs_dlq_message_retention_seconds" {
  description = "Dev SQS DLQ message retention in seconds for failure inspection during development."
  type        = number
  default     = 345600
}

variable "dev_sqs_max_receive_count" {
  description = "Dev SQS receive attempts before moving a message to the DLQ."
  type        = number
  default     = 3
}

variable "dev_sqs_receive_wait_time_seconds" {
  description = "Dev SQS long polling wait time in seconds."
  type        = number
  default     = 10
}

variable "dev_sqs_delay_seconds" {
  description = "Dev SQS delay for new messages in seconds."
  type        = number
  default     = 0
}

variable "dev_sqs_max_message_size" {
  description = "Dev SQS maximum message size in bytes."
  type        = number
  default     = 262144
}

variable "dev_sqs_managed_sse_enabled" {
  description = "Whether Dev SQS managed server-side encryption is enabled."
  type        = bool
  default     = true
}

variable "enable_dev_s3_raw_bucket" {
  description = "Whether to manage Dev S3 Raw Bucket in terraform/environments/dev."
  type        = bool
  default     = true
}

variable "dev_raw_bucket_name" {
  description = "Optional explicit Dev S3 Raw Bucket name. Keep null to use the module naming convention."
  type        = string
  default     = null
}

variable "enable_dev_profile_image_bucket" {
  description = "Whether to manage Dev profile image upload S3 bucket."
  type        = bool
  default     = true
}

variable "dev_profile_image_bucket_name" {
  description = "Optional explicit Dev profile image S3 bucket name. Keep null to use the module naming convention."
  type        = string
  default     = null
}

variable "dev_profile_image_allowed_origins" {
  description = "Allowed CORS origins for Dev profile image Presigned PUT upload."
  type        = list(string)
  default     = ["*"]
}

variable "dev_profile_image_object_key_prefix" {
  description = "S3 object key prefix used by Backend profile image upload in Dev."
  type        = string
  default     = "uploads/profile"
}


variable "enable_dev_notification_sns" {
  description = "Whether to manage Dev notification SNS topic for Backend notification publish."
  type        = bool
  default     = true
}

variable "dev_notification_sns_topic_name" {
  description = "Optional explicit Dev notification SNS topic name. Keep null to use the module naming convention."
  type        = string
  default     = null
}

variable "dev_notification_sns_display_name" {
  description = "Dev notification SNS topic display name."
  type        = string
  default     = "MoMent Dev Notification"
}

variable "dev_notification_sns_kms_master_key_id" {
  description = "Optional KMS key ID or alias for Dev notification SNS topic encryption. Keep null unless KMS encryption is explicitly required."
  type        = string
  default     = null
}


variable "enable_dev_data_pipeline" {
  description = "Whether to create Dev EventBridge Scheduler and Lambda Collector for public data pipeline validation."
  type        = bool
  default     = true
}


variable "enable_dev_public_data_secrets" {
  description = "Whether to create Dev public data Secrets Manager secret containers for Lambda Collector. Secret values are managed out-of-band."
  type        = bool
  default     = false
}

variable "enable_prod_data_pipeline" {
  description = "Whether to create Prod EventBridge Scheduler and Lambda Collector. Disabled by default for cost saving."
  type        = bool
  default     = false
}

variable "data_pipeline_public_data_api_url" {
  description = "Legacy single Public Data API URL. Prefer data_pipeline_public_data_sources_json for M2-DATA-02."
  type        = string
  default     = ""
}

variable "data_pipeline_public_data_sources_json" {
  description = "JSON array of public data source configs for Lambda Collector."
  type        = string
  default     = "[]"

  validation {
    condition     = can(jsondecode(var.data_pipeline_public_data_sources_json))
    error_message = "data_pipeline_public_data_sources_json must be valid JSON."
  }
}

variable "enable_lambda_collector_secrets_manager_read" {
  description = "Whether Lambda Collector can read public data API keys from Secrets Manager."
  type        = bool
  default     = true
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

variable "dev_data_pipeline_schedule_state" {
  description = "Dev EventBridge Scheduler state. Keep DISABLED unless scheduled execution is intentionally required."
  type        = string
  default     = "DISABLED"
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

variable "enable_dev_redis" {
  description = "Whether to create Dev ElastiCache Redis by default for development validation."
  type        = bool
  default     = true
}

variable "enable_prod_redis" {
  description = "Whether to create Prod ElastiCache Redis. Disabled by default for cost saving."
  type        = bool
  default     = false
}

variable "redis_engine_version" {
  description = "Redis engine version."
  type        = string
  default     = "7.0"
}

variable "redis_node_type" {
  description = "Redis node type for practice and validation."
  type        = string
  default     = "cache.t3.micro"
}

variable "dev_redis_node_type" {
  description = "Dev Redis node type for cost-optimized validation."
  type        = string
  default     = "cache.t3.micro"
}

variable "dev_redis_num_cache_clusters" {
  description = "Number of cache clusters for Dev Redis. Minimum 1 for single-node dev setup."
  type        = number
  default     = 1
}

variable "enable_dev_rds" {
  description = "Whether to create Dev RDS PostgreSQL by default for development validation."
  type        = bool
  default     = true
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

variable "dev_rds_instance_class" {
  description = "Dev RDS instance class for practice and validation."
  type        = string
  default     = "db.t4g.micro"
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

variable "dev_rds_allocated_storage" {
  description = "Allocated Dev RDS storage size in GiB."
  type        = number
  default     = 20
}

variable "dev_rds_max_allocated_storage" {
  description = "Maximum Dev RDS storage size in GiB for autoscaling."
  type        = number
  default     = 100
}

variable "dev_rds_multi_az" {
  description = "Whether Dev RDS PostgreSQL uses Multi-AZ deployment. Disabled by default for cost saving."
  type        = bool
  default     = false
}

variable "dev_rds_backup_retention_period" {
  description = "Backup retention period in days for Dev RDS PostgreSQL."
  type        = number
  default     = 1
}

variable "dev_rds_backup_window" {
  description = "Preferred backup window for Dev RDS PostgreSQL."
  type        = string
  default     = "18:00-19:00"
}

variable "dev_rds_maintenance_window" {
  description = "Preferred maintenance window for Dev RDS PostgreSQL."
  type        = string
  default     = "sun:19:00-sun:20:00"
}

variable "dev_rds_deletion_protection" {
  description = "Whether deletion protection is enabled for Dev RDS PostgreSQL."
  type        = bool
  default     = false
}

variable "dev_rds_skip_final_snapshot" {
  description = "Whether to skip final snapshot on Dev RDS destroy."
  type        = bool
  default     = true
}

variable "dev_rds_final_snapshot_identifier" {
  description = "Final snapshot identifier for Dev RDS. Used only when dev_rds_skip_final_snapshot is false."
  type        = string
  default     = null
}

variable "enable_dev_opensearch" {
  description = "Whether to create Dev OpenSearch by default for development validation."
  type        = bool
  default     = true
}

variable "enable_prod_opensearch" {
  description = "Whether to create Prod OpenSearch. Disabled by default for cost saving."
  type        = bool
  default     = false
}

variable "create_opensearch_service_linked_role" {
  description = "Whether to create the account-level OpenSearch service-linked role. Keep true only when the role does not already exist in the AWS account."
  type        = bool
  default     = true
}

variable "opensearch_engine_version" {
  description = "OpenSearch engine version."
  type        = string
  default     = "OpenSearch_2.17"
}

variable "dev_opensearch_instance_type" {
  description = "Dev OpenSearch instance type for cost-optimized validation."
  type        = string
  default     = "t3.small.search"
}

variable "prod_opensearch_instance_type" {
  description = "Prod OpenSearch instance type used only when Prod OpenSearch is explicitly enabled."
  type        = string
  default     = "t3.medium.search"
}

variable "prod_opensearch_instance_count" {
  description = "Number of Prod OpenSearch data nodes when Prod OpenSearch is enabled."
  type        = number
  default     = 2
}

variable "prod_opensearch_dedicated_master_enabled" {
  description = "Whether Prod OpenSearch dedicated master nodes are enabled when Prod OpenSearch is explicitly enabled."
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
}

variable "prod_opensearch_zone_awareness_enabled" {
  description = "Whether Prod OpenSearch uses zone awareness when explicitly enabled."
  type        = bool
  default     = true
}

variable "prod_opensearch_availability_zone_count" {
  description = "Availability zone count for Prod OpenSearch zone awareness."
  type        = number
  default     = 2
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

variable "dev_opensearch_ebs_volume_size" {
  description = "Dev OpenSearch EBS volume size in GiB."
  type        = number
  default     = 10
}

variable "prod_opensearch_ebs_volume_size" {
  description = "Prod OpenSearch EBS volume size in GiB when Prod OpenSearch is enabled."
  type        = number
  default     = 50
}

# ─── Edge Layer ──────────────────────────────────────────────────────────────
variable "enable_edge" {
  description = "Edge 계층(CloudFront/WAF/ACM) 생성 여부"
  type        = bool
  default     = false
}

variable "enable_waf" {
  description = "WAF Web ACL 생성 여부"
  type        = bool
  default     = true
}

variable "edge_domain_name" {
  description = "커스텀 도메인명 (없으면 빈 문자열)"
  type        = string
  default     = ""
}

variable "edge_subject_alternative_names" {
  description = "ACM 추가 도메인 목록"
  type        = list(string)
  default     = []
}

variable "create_route53_hosted_zone" {
  description = "Route53 Hosted Zone 신규 생성 여부"
  type        = bool
  default     = false
}

variable "prod_alb_dns_name" {
  description = "Prod ALB DNS명 (CloudFront Origin). Prod ALB 생성 전엔 빈 문자열"
  type        = string
  default     = ""
}

variable "prod_alb_https_enabled" {
  description = "CloudFront → Prod ALB HTTPS 사용 여부"
  type        = bool
  default     = false
}

variable "cloudfront_secret_header_value" {
  description = "X-CloudFront-Secret 헤더 값 (ALB 직접 접근 차단용)"
  type        = string
  sensitive   = true
  default     = "moment-cf-secret-change-me"
}

variable "cloudfront_price_class" {
  description = "CloudFront 요금제 클래스"
  type        = string
  default     = "PriceClass_All"
}

# ──────────────────────────────────────────────────────────────────────────────
# Shared environment dependency inputs
# ──────────────────────────────────────────────────────────────────────────────

variable "shared_lambda_collector_role_arn" {
  description = "Lambda Collector IAM role ARN managed by shared environment. If empty, Dev data pipeline looks up the default moment-dev Lambda Collector role by name."
  type        = string
  default     = ""
}

variable "shared_eks_cluster_role_arn" {
  description = "EKS Cluster IAM role ARN managed by shared environment. Required before enabling Dev EKS apply."
  type        = string
  default     = ""
}

variable "shared_eks_node_role_arn" {
  description = "EKS Node IAM role ARN managed by shared environment. Required before enabling Dev nodegroups apply."
  type        = string
  default     = ""
}

variable "enable_dev_iam" {
  description = "Whether to manage Dev environment IAM roles and policies from terraform/environments/dev."
  type        = bool
  default     = true
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
    "repo:Team-msp-architect-2026/msp-team04-infra:ref:refs/heads/develop",
    "repo:Team-msp-architect-2026/msp-team04-backend:ref:refs/heads/develop",
    "repo:Team-msp-architect-2026/msp-team04-ai:ref:refs/heads/develop"
  ]
}

variable "github_oidc_provider_arn" {
  description = "Existing account-level GitHub Actions OIDC Provider ARN."
  type        = string
  default     = "arn:aws:iam::611058323802:oidc-provider/token.actions.githubusercontent.com"
}

variable "enable_irsa_roles" {
  description = "Whether to create IRSA roles for EKS service accounts."
  type        = bool
  default     = false
}

variable "create_eks_oidc_provider" {
  description = "Whether to create EKS OIDC provider."
  type        = bool
  default     = false
}

variable "eks_oidc_issuer_url" {
  description = "EKS OIDC issuer URL. Required when enable_irsa_roles is true."
  type        = string
  default     = ""
}

variable "eks_oidc_provider_arn" {
  description = "EKS OIDC provider ARN. Required when enable_irsa_roles is true."
  type        = string
  default     = ""
}

variable "irsa_service_accounts" {
  description = "Map of IRSA service accounts to create roles for."
  type = map(object({
    namespace = string
    name      = string
  }))
  default = {}
}


variable "dev_profile_image_public_read_enabled" {
  description = "Whether Dev profile image objects are publicly readable with s3:GetObject for direct app display."
  type        = bool
  default     = true
}

variable "enable_dev_external_secrets_irsa" {
  description = "Whether to create Dev External Secrets Operator IRSA role and runtime secret containers."
  type        = bool
  default     = false
}

variable "dev_external_secrets_namespace" {
  description = "Namespace where External Secrets Operator is installed in Dev EKS."
  type        = string
  default     = "external-secrets"
}

variable "dev_external_secrets_service_account_name" {
  description = "ServiceAccount name used by External Secrets Operator in Dev EKS."
  type        = string
  default     = "external-secrets"
}


variable "enable_dev_alerting_slack_notifier" {
  description = "Whether to create Dev CloudWatch alert SNS topic and Slack notifier Lambda."
  type        = bool
  default     = true
}

variable "enable_dev_cloudwatch_alarms" {
  description = "Whether to create Dev CloudWatch metric alarms for Terraform-managed AWS resources."
  type        = bool
  default     = true
}

variable "dev_alerting_slack_webhook_secret_name" {
  description = "Secrets Manager secret name for Dev monitoring Slack webhook. Secret value is managed out-of-band."
  type        = string
  default     = "moment/dev/monitoring/slack-alert-webhook"
}

variable "dev_alerting_sns_topic_name" {
  description = "Optional explicit Dev monitoring alert SNS topic name."
  type        = string
  default     = null
}

variable "dev_alerting_application_load_balancer_tag_selectors" {
  description = "Dev AWS Load Balancer Controller managed ALB tag selectors for CloudWatch alarms."
  type = map(object({
    tags = map(string)
  }))
  default = {
    backend_api = {
      tags = {
        "ingress.k8s.aws/resource" = "LoadBalancer"
        "ingress.k8s.aws/stack"    = "moment-dev/backend-api"
        "elbv2.k8s.aws/cluster"    = "moment-dev-eks-cluster"
      }
    }
  }
}

variable "dev_alerting_target_group_tag_selectors" {
  description = "Dev AWS Load Balancer Controller managed Target Group tag selectors for CloudWatch alarms."
  type = map(object({
    load_balancer_key = string
    tags              = map(string)
  }))
  default = {
    backend_api = {
      load_balancer_key = "backend_api"
      tags = {
        "ingress.k8s.aws/resource" = "moment-dev/backend-api-backend-api:8080"
        "ingress.k8s.aws/stack"    = "moment-dev/backend-api"
        "elbv2.k8s.aws/cluster"    = "moment-dev-eks-cluster"
      }
    }
  }
}

variable "enable_dev_karpenter" {
  description = "Whether to create the Dev Karpenter AWS resources (controller IRSA, node role, interruption queue, node subnets)."
  type        = bool
  default     = true
}

variable "dev_karpenter_node_subnet_cidrs" {
  description = "Dev Karpenter node subnet CIDRs, one per AZ (a, c). Sized for VPC CNI Prefix Delegation /28 reservations; must stay inside dev_vpc_cidr and outside the existing subnets."
  type        = list(string)
  default = [
    "10.20.32.0/20",
    "10.20.48.0/20"
  ]
}

variable "enable_dev_legacy_workload_nodegroups" {
  description = "Keep the legacy batch/ai managed node groups. Set false after batch-job/ai-service run on Karpenter NodePools (docs/karpenter.md)."
  type        = bool
  default     = true
}

variable "dev_karpenter_create_spot_service_linked_role" {
  description = "Create AWSServiceRoleForEC2Spot with the Dev Karpenter module. Set true only if the account does not have it yet (the role is account-wide; the legacy Spot managed node groups usually created it already)."
  type        = bool
  default     = false
}
