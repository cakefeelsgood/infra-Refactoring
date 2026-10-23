output "project_name" {
  description = "Project name."
  value       = var.project_name
}

output "env" {
  description = "Terraform environment name."
  value       = var.env
}

output "primary_region" {
  description = "Primary AWS region."
  value       = var.primary_region
}

# ── Dev ECR Outputs ───────────────────────────────────────────────────────────

output "dev_ecr_repository_names" {
  description = "Dev ECR Repository names."
  value       = module.dev_ecr.repository_names
}

output "dev_ecr_repository_urls" {
  description = "Dev ECR Repository URLs for GitHub Actions."
  value       = module.dev_ecr.repository_urls
}

output "dev_ecr_repository_arns" {
  description = "Dev ECR Repository ARNs."
  value       = module.dev_ecr.repository_arns
}

output "dev_backend_repository_url" {
  description = "Dev Backend API ECR Repository URL."
  value       = module.dev_ecr.backend_repository_url
}

output "dev_ai_service_repository_url" {
  description = "Dev AI Service ECR Repository URL."
  value       = module.dev_ecr.ai_service_repository_url
}

output "dev_batch_repository_url" {
  description = "Dev Batch Job ECR Repository URL."
  value       = module.dev_ecr.batch_repository_url
}

# ── Dev VPC Outputs ───────────────────────────────────────────────────────────

output "dev_vpc_id" {
  description = "Dev VPC ID."
  value       = try(module.dev_vpc[0].dev_vpc_id, null)
}

output "dev_vpc_cidr" {
  description = "Dev VPC CIDR block."
  value       = try(module.dev_vpc[0].dev_vpc_cidr, null)
}

output "dev_public_subnet_ids" {
  description = "Dev public subnet IDs."
  value       = try(module.dev_vpc[0].dev_public_subnet_ids, [])
}

output "dev_private_app_subnet_ids" {
  description = "Dev private app subnet IDs."
  value       = try(module.dev_vpc[0].dev_private_app_subnet_ids, [])
}

output "dev_private_data_subnet_ids" {
  description = "Dev private data subnet IDs."
  value       = try(module.dev_vpc[0].dev_private_data_subnet_ids, [])
}

output "dev_reserved_data_subnet_ids" {
  description = "Dev reserved private data subnet IDs."
  value       = try(module.dev_vpc[0].dev_private_data_subnet_ids, [])
}

output "dev_tgw_subnet_ids" {
  description = "Dev TGW attachment subnet IDs."
  value       = try(module.dev_vpc[0].dev_tgw_subnet_ids, [])
}

output "dev_public_route_table_id" {
  description = "Dev public route table ID."
  value       = try(module.dev_vpc[0].dev_public_route_table_id, null)
}

output "dev_private_app_route_table_id" {
  description = "Dev private app route table ID."
  value       = try(module.dev_vpc[0].dev_private_app_route_table_id, null)
}

output "dev_private_data_route_table_id" {
  description = "Dev private data route table ID."
  value       = try(module.dev_vpc[0].dev_private_data_route_table_id, null)
}

output "dev_tgw_route_table_id" {
  description = "Dev TGW subnet route table ID."
  value       = try(module.dev_vpc[0].dev_tgw_route_table_id, null)
}

# ── Dev Security Group / Endpoint Outputs ─────────────────────────────────────

output "dev_security_group_ids" {
  description = "Dev service security group IDs."
  value       = try(module.dev_security_group[0].service_security_group_ids, {})
}

output "dev_s3_gateway_endpoint_id" {
  description = "Dev S3 Gateway Endpoint ID."
  value       = try(module.dev_vpc_endpoint[0].s3_gateway_endpoint_id, null)
}

output "dev_interface_endpoint_ids" {
  description = "Dev Interface Endpoint IDs."
  value       = try(module.dev_vpc_endpoint[0].interface_endpoint_ids, {})
}

# ── Shared Dependency Inputs ──────────────────────────────────────────────────

output "shared_lambda_collector_role_arn" {
  description = "Lambda Collector IAM role ARN supplied from shared environment."
  value       = var.enable_dev_iam ? module.dev_iam[0].lambda_collector_role_arn : null
}

output "dev_raw_bucket_name" {
  description = "Dev S3 Raw Bucket name."
  value       = try(module.dev_s3_raw_bucket[0].raw_bucket_name, null)
}

output "dev_raw_bucket_arn" {
  description = "Dev S3 Raw Bucket ARN."
  value       = try(module.dev_s3_raw_bucket[0].raw_bucket_arn, null)
}

output "dev_raw_bucket_access_policy_arn" {
  description = "Dev S3 Raw Bucket access policy ARN."
  value       = try(module.dev_s3_raw_bucket[0].raw_bucket_access_policy_arn, null)
}

output "dev_profile_image_bucket_name" {
  description = "Dev profile image S3 bucket name."
  value       = try(module.dev_profile_image_bucket[0].bucket_name, null)
}

output "dev_profile_image_bucket_arn" {
  description = "Dev profile image S3 bucket ARN."
  value       = try(module.dev_profile_image_bucket[0].bucket_arn, null)
}

output "dev_profile_image_public_url_base" {
  description = "Dev profile image public URL base for Backend PROFILE_IMAGE_PUBLIC_URL_BASE."
  value       = try(module.dev_profile_image_bucket[0].public_url_base, null)
}

output "dev_profile_image_object_key_prefix" {
  description = "Dev profile image object key prefix for Backend PROFILE_IMAGE_KEY_PREFIX."
  value       = try(module.dev_profile_image_bucket[0].object_key_prefix, null)
}


output "dev_notification_sns_topic_name" {
  description = "Dev notification SNS topic name."
  value       = try(module.dev_notification_sns[0].topic_name, null)
}

output "dev_notification_sns_topic_arn" {
  description = "Dev notification SNS topic ARN for Backend NOTIFICATION_SNS_TOPIC_ARN."
  value       = try(module.dev_notification_sns[0].topic_arn, null)
}


output "shared_eks_cluster_role_arn" {
  description = "EKS Cluster IAM role ARN supplied from shared environment."
  value       = var.enable_dev_iam ? module.dev_iam[0].eks_cluster_role_arn : null
}

output "shared_eks_node_role_arn" {
  description = "EKS Node IAM role ARN supplied from shared environment."
  value       = var.enable_dev_iam ? module.dev_iam[0].eks_node_role_arn : null
}

# ── Dev SQS Outputs ───────────────────────────────────────────────────────────

output "dev_sqs_queue_name" {
  description = "Dev SQS queue name."
  value       = try(module.dev_sqs[0].queue_name, null)
}

output "dev_sqs_queue_url" {
  description = "Dev SQS queue URL."
  value       = try(module.dev_sqs[0].queue_url, null)
}

output "dev_sqs_queue_arn" {
  description = "Dev SQS queue ARN."
  value       = try(module.dev_sqs[0].queue_arn, null)
}

output "dev_sqs_dlq_name" {
  description = "Dev SQS DLQ name."
  value       = try(module.dev_sqs[0].dlq_name, null)
}

output "dev_sqs_dlq_url" {
  description = "Dev SQS DLQ URL."
  value       = try(module.dev_sqs[0].dlq_url, null)
}

output "dev_sqs_dlq_arn" {
  description = "Dev SQS DLQ ARN."
  value       = try(module.dev_sqs[0].dlq_arn, null)
}

# ── Dev EKS Outputs ───────────────────────────────────────────────────────────

output "dev_eks_enabled" {
  description = "Whether Dev EKS cluster creation is enabled."
  value       = var.enable_dev_eks
}

output "dev_eks_cluster_name" {
  description = "Dev EKS cluster name."
  value       = try(module.dev_eks[0].cluster_name, null)
}

output "dev_eks_cluster_arn" {
  description = "Dev EKS cluster ARN."
  value       = try(module.dev_eks[0].cluster_arn, null)
}

output "dev_eks_cluster_endpoint" {
  description = "Dev EKS cluster API endpoint."
  value       = try(module.dev_eks[0].cluster_endpoint, null)
}

output "dev_eks_cluster_ca_certificate" {
  description = "Dev EKS cluster certificate authority data."
  value       = try(module.dev_eks[0].cluster_certificate_authority_data, null)
}

output "dev_eks_cluster_version" {
  description = "Dev EKS Kubernetes version."
  value       = try(module.dev_eks[0].cluster_version, null)
}

output "dev_eks_cluster_status" {
  description = "Dev EKS cluster status."
  value       = try(module.dev_eks[0].cluster_status, null)
}

output "dev_eks_cluster_security_group_id" {
  description = "Dev EKS cluster security group ID."
  value       = try(module.dev_eks[0].cluster_security_group_id, null)
}

output "dev_eks_oidc_issuer_url" {
  description = "Dev EKS OIDC issuer URL."
  value       = try(module.dev_eks[0].cluster_oidc_issuer_url, null)
}

output "dev_eks_oidc_provider_arn" {
  description = "Dev EKS IAM OIDC Provider ARN."
  value       = try(module.dev_eks[0].eks_oidc_provider_arn, null)
}

output "dev_eks_addon_versions" {
  description = "Dev EKS managed add-on versions."
  value       = try(module.dev_eks[0].addon_versions, {})
}

output "dev_eks_ebs_csi_irsa_role_arn" {
  description = "Dev EKS EBS CSI IRSA role ARN."
  value       = try(module.dev_eks[0].ebs_csi_irsa_role_arn, null)
}

output "dev_eks_node_group_names" {
  description = "Dev EKS managed node group names."
  value       = var.enable_dev_eks && var.enable_dev_nodegroups ? module.dev_eks_nodegroups[0].node_group_names : {}
}

output "dev_eks_node_group_arns" {
  description = "Dev EKS managed node group ARNs."
  value       = var.enable_dev_eks && var.enable_dev_nodegroups ? module.dev_eks_nodegroups[0].node_group_arns : {}
}

output "dev_eks_node_group_statuses" {
  description = "Dev EKS managed node group statuses."
  value       = var.enable_dev_eks && var.enable_dev_nodegroups ? module.dev_eks_nodegroups[0].node_group_statuses : {}
}

output "dev_eks_node_role_arn" {
  description = "IAM role ARN used by Dev EKS managed node groups."
  value       = var.enable_dev_iam ? module.dev_iam[0].eks_node_role_arn : null
}

# ── Dev Data Pipeline Outputs ─────────────────────────────────────────────────

output "dev_data_pipeline_enabled" {
  description = "Whether Dev data pipeline resources are enabled."
  value       = var.enable_dev_data_pipeline
}

output "dev_data_pipeline_lambda_function_name" {
  description = "Dev data collector Lambda function name."
  value       = try(module.dev_data_pipeline[0].lambda_function_name, null)
}

output "dev_data_pipeline_lambda_function_arn" {
  description = "Dev data collector Lambda function ARN."
  value       = try(module.dev_data_pipeline[0].lambda_function_arn, null)
}

output "dev_data_pipeline_scheduler_schedule_group_name" {
  description = "Dev EventBridge Scheduler schedule group name."
  value       = try(module.dev_data_pipeline[0].scheduler_schedule_group_name, null)
}

output "dev_data_pipeline_scheduler_schedule_name" {
  description = "Dev EventBridge Scheduler schedule name."
  value       = try(module.dev_data_pipeline[0].scheduler_schedule_name, null)
}

output "dev_data_pipeline_scheduler_schedule_arn" {
  description = "Dev EventBridge Scheduler schedule ARN."
  value       = try(module.dev_data_pipeline[0].scheduler_schedule_arn, null)
}

# ── Dev Data Tier Outputs ─────────────────────────────────────────────────────

output "dev_redis_endpoint" {
  description = "Dev Redis primary endpoint."
  value       = var.enable_dev_redis ? module.dev_redis[0].redis_primary_endpoint : null
}

output "dev_redis_port" {
  description = "Dev Redis port."
  value       = var.enable_dev_redis ? module.dev_redis[0].redis_port : null
}

output "dev_redis_subnet_group_name" {
  description = "Dev Redis subnet group name."
  value       = var.enable_dev_redis ? module.dev_redis[0].redis_subnet_group_name : null
}

output "dev_rds_endpoint" {
  description = "Dev RDS endpoint."
  value       = var.enable_dev_rds ? module.dev_rds[0].db_endpoint : null
}

output "dev_rds_port" {
  description = "Dev RDS port."
  value       = var.enable_dev_rds ? module.dev_rds[0].db_port : null
}

output "dev_rds_database_name" {
  description = "Dev RDS database name."
  value       = var.enable_dev_rds ? module.dev_rds[0].db_name : null
}

output "dev_rds_subnet_group_name" {
  description = "Dev RDS subnet group name."
  value       = var.enable_dev_rds ? module.dev_rds[0].db_subnet_group_name : null
}

output "dev_rds_master_user_secret_arn" {
  description = "Dev RDS master user password secret ARN managed by RDS."
  value       = var.enable_dev_rds ? module.dev_rds[0].master_user_secret_arn : null
  sensitive   = true
}

output "dev_opensearch_domain_name" {
  description = "Dev OpenSearch domain name."
  value       = var.enable_dev_opensearch ? module.dev_opensearch[0].domain_name : null
}

output "dev_opensearch_domain_arn" {
  description = "Dev OpenSearch domain ARN."
  value       = var.enable_dev_opensearch ? module.dev_opensearch[0].domain_arn : null
}

output "dev_opensearch_endpoint" {
  description = "Dev OpenSearch endpoint."
  value       = var.enable_dev_opensearch ? module.dev_opensearch[0].endpoint : null
}

output "dev_opensearch_dashboard_endpoint" {
  description = "Dev OpenSearch dashboard endpoint."
  value       = var.enable_dev_opensearch ? module.dev_opensearch[0].dashboard_endpoint : null
}

output "dev_external_secrets_irsa_role_arn" {
  description = "Dev External Secrets Operator IRSA role ARN."
  value       = try(module.dev_external_secrets_irsa[0].role_arn, null)
}

output "dev_runtime_secret_arns" {
  description = "Dev runtime Secrets Manager secret ARNs used by External Secrets Operator."
  value = {
    for key, secret in aws_secretsmanager_secret.dev_runtime : key => secret.arn
  }
}

output "dev_public_data_secret_arns" {
  description = "ARNs of Dev public data Secrets Manager secrets for Lambda Collector."
  value = {
    for key, secret in aws_secretsmanager_secret.dev_public_data : key => secret.arn
  }
}


output "dev_alerting_sns_topic_arn" {
  description = "Dev CloudWatch monitoring alert SNS topic ARN."
  value       = try(module.dev_alerting_slack_notifier[0].sns_topic_arn, null)
}

output "dev_alerting_slack_notifier_lambda_name" {
  description = "Dev CloudWatch Slack notifier Lambda function name."
  value       = try(module.dev_alerting_slack_notifier[0].lambda_function_name, null)
}

output "dev_alerting_slack_webhook_secret_arn" {
  description = "Dev Slack webhook Secrets Manager secret ARN for monitoring alerts."
  value       = try(module.dev_alerting_slack_notifier[0].slack_webhook_secret_arn, null)
}

output "dev_cloudwatch_alert_alarm_names" {
  description = "Dev CloudWatch monitoring alert alarm names."
  value       = try(module.dev_alerting_slack_notifier[0].cloudwatch_alarm_names, [])
}

output "dev_karpenter_node_subnet_ids" {
  description = "Dev Karpenter node subnet IDs (karpenter.sh/discovery tagged)."
  value       = try(module.dev_vpc[0].dev_karpenter_node_subnet_ids, [])
}

output "dev_karpenter_controller_role_arn" {
  description = "Dev Karpenter controller IRSA role ARN. Referenced by gitops/argocd/dev/applications/karpenter-dev.yaml."
  value       = try(module.dev_karpenter[0].controller_role_arn, null)
}

output "dev_karpenter_node_role_name" {
  description = "Dev Karpenter node role name. Referenced by gitops/apps/dev/karpenter/ec2nodeclass.yaml."
  value       = try(module.dev_karpenter[0].node_role_name, null)
}

output "dev_karpenter_interruption_queue_name" {
  description = "Dev Karpenter interruption SQS queue name. Referenced by Karpenter settings.interruptionQueue."
  value       = try(module.dev_karpenter[0].interruption_queue_name, null)
}
