output "project_name" {
  description = "Project name."
  value       = var.project_name
}

output "env" {
  description = "Environment name."
  value       = var.env
}

output "primary_region" {
  description = "Primary AWS region."
  value       = var.primary_region
}

output "prod_state_key" {
  description = "Remote state key for the Prod Terraform environment."
  value       = "prod/terraform.tfstate"
}

output "prod_vpc_id" {
  description = "Prod VPC ID."
  value       = try(module.prod_vpc[0].prod_vpc_id, null)
}

output "prod_private_app_subnet_ids" {
  description = "Prod private app subnet IDs."
  value       = try(module.prod_vpc[0].prod_private_app_subnet_ids, [])
}

output "prod_private_data_subnet_ids" {
  description = "Prod private data subnet IDs."
  value       = try(module.prod_vpc[0].prod_private_data_subnet_ids, [])
}

output "prod_security_group_ids" {
  description = "Prod service security group IDs."
  value       = try(module.prod_security_group[0].service_security_group_ids, {})
}

output "prod_sqs_queue_url" {
  description = "Prod SQS main queue URL."
  value       = try(module.prod_sqs[0].queue_url, null)
}

output "prod_sqs_queue_arn" {
  description = "Prod SQS main queue ARN."
  value       = try(module.prod_sqs[0].queue_arn, null)
}

output "prod_raw_bucket_name" {
  description = "Prod S3 Raw Bucket name."
  value       = try(module.prod_s3_raw_bucket[0].raw_bucket_name, null)
}

output "prod_raw_bucket_arn" {
  description = "Prod S3 Raw Bucket ARN."
  value       = try(module.prod_s3_raw_bucket[0].raw_bucket_arn, null)
}

output "prod_raw_bucket_access_policy_arn" {
  description = "Prod S3 Raw Bucket access policy ARN."
  value       = try(module.prod_s3_raw_bucket[0].raw_bucket_access_policy_arn, null)
}

output "prod_profile_image_bucket_name" {
  description = "Prod profile image S3 bucket name."
  value       = try(module.prod_profile_image_bucket[0].bucket_name, null)
}

output "prod_profile_image_bucket_arn" {
  description = "Prod profile image S3 bucket ARN."
  value       = try(module.prod_profile_image_bucket[0].bucket_arn, null)
}

output "prod_profile_image_public_url_base" {
  description = "Prod profile image public URL base for Backend PROFILE_IMAGE_PUBLIC_URL_BASE."
  value       = try(module.prod_profile_image_bucket[0].public_url_base, null)
}

output "prod_profile_image_object_key_prefix" {
  description = "Prod profile image object key prefix for Backend PROFILE_IMAGE_KEY_PREFIX."
  value       = try(module.prod_profile_image_bucket[0].object_key_prefix, null)
}


output "prod_notification_sns_topic_name" {
  description = "Prod notification SNS topic name."
  value       = try(module.prod_notification_sns[0].topic_name, null)
}

output "prod_notification_sns_topic_arn" {
  description = "Prod notification SNS topic ARN for Backend NOTIFICATION_SNS_TOPIC_ARN."
  value       = try(module.prod_notification_sns[0].topic_arn, null)
}


output "prod_data_pipeline_lambda_function_name" {
  description = "Prod Lambda Collector function name."
  value       = try(module.prod_data_pipeline[0].lambda_function_name, null)
}

output "prod_eks_cluster_name" {
  description = "Prod EKS cluster name."
  value       = try(module.prod_eks[0].cluster_name, null)
}

output "prod_eks_cluster_endpoint" {
  description = "Prod EKS cluster API endpoint."
  value       = try(module.prod_eks[0].cluster_endpoint, null)
}

output "prod_redis_endpoint" {
  description = "Prod Redis primary endpoint."
  value       = try(module.prod_redis[0].redis_primary_endpoint, null)
}

output "prod_rds_endpoint" {
  description = "Prod RDS endpoint."
  value       = try(module.prod_rds[0].db_endpoint, null)
}

output "prod_opensearch_endpoint" {
  description = "Prod OpenSearch VPC endpoint."
  value       = try(module.prod_opensearch[0].endpoint, null)
}

output "edge_cloudfront_domain_name" {
  description = "CloudFront distribution domain name."
  value       = try(module.edge[0].cloudfront_domain_name, null)
}

output "prod_nodegroups_wiring_deferred_to_m2_eks_04" {
  description = "Prod Managed NodeGroup detailed wiring is intentionally deferred to M2-EKS-04."
  value       = true
}

output "prod_ecr_repository_names" {
  description = "Prod ECR Repository names."
  value       = var.enable_prod_ecr ? module.prod_ecr[0].repository_names : {}
}

output "prod_ecr_repository_urls" {
  description = "Prod ECR Repository URLs."
  value       = var.enable_prod_ecr ? module.prod_ecr[0].repository_urls : {}
}

output "prod_ecr_repository_arns" {
  description = "Prod ECR Repository ARNs."
  value       = var.enable_prod_ecr ? module.prod_ecr[0].repository_arns : {}
}

output "prod_backend_repository_url" {
  description = "Prod Backend API ECR Repository URL."
  value       = var.enable_prod_ecr ? module.prod_ecr[0].backend_repository_url : null
}

output "prod_ai_service_repository_url" {
  description = "Prod AI Service ECR Repository URL."
  value       = var.enable_prod_ecr ? module.prod_ecr[0].ai_service_repository_url : null
}

output "prod_batch_repository_url" {
  description = "Prod Batch Job ECR Repository URL."
  value       = var.enable_prod_ecr ? module.prod_ecr[0].batch_repository_url : null
}

output "prod_lambda_collector_role_arn" {
  description = "Prod Lambda Collector IAM role ARN."
  value       = var.enable_prod_iam ? module.prod_iam[0].lambda_collector_role_arn : null
}

output "prod_eks_cluster_role_arn" {
  description = "Prod EKS cluster IAM role ARN."
  value       = var.enable_prod_iam ? module.prod_iam[0].eks_cluster_role_arn : null
}

output "prod_eks_node_role_arn" {
  description = "Prod EKS node IAM role ARN."
  value       = var.enable_prod_iam ? module.prod_iam[0].eks_node_role_arn : null
}

output "prod_eks_oidc_provider_arn" {
  description = "Prod EKS OIDC provider ARN."
  value       = try(module.prod_eks[0].eks_oidc_provider_arn, null)
}

output "prod_eks_oidc_provider_url" {
  description = "Prod EKS OIDC provider URL without https://."
  value       = try(module.prod_eks[0].eks_oidc_provider_url, null)
}

output "prod_external_secrets_irsa_role_arn" {
  description = "Prod External Secrets Operator IRSA role ARN."
  value       = try(module.prod_external_secrets_irsa[0].role_arn, null)
}

output "prod_runtime_secret_arns" {
  description = "Prod runtime Secrets Manager secret ARNs used by External Secrets Operator."
  value = {
    for key, secret in aws_secretsmanager_secret.prod_runtime : key => secret.arn
  }
}

output "prod_rds_master_user_secret_arn" {
  description = "Prod RDS managed master user secret ARN."
  value       = try(module.prod_rds[0].master_user_secret_arn, null)
  sensitive   = true
}

output "prod_public_data_secret_arns" {
  description = "ARNs of Prod public data Secrets Manager secrets for Lambda Collector."
  value = {
    for key, secret in aws_secretsmanager_secret.prod_public_data : key => secret.arn
  }
}


output "prod_workload_irsa_role_arns" {
  description = "Prod workload IRSA role ARNs keyed by workload."
  value       = try(module.prod_workload_irsa[0].role_arns, {})
}

output "prod_workload_service_account_annotations" {
  description = "Prod workload Kubernetes ServiceAccount annotations for IRSA."
  value       = try(module.prod_workload_irsa[0].service_account_annotations, {})
}


output "prod_alerting_sns_topic_arn" {
  description = "Prod CloudWatch monitoring alert SNS topic ARN."
  value       = try(module.prod_alerting_slack_notifier[0].sns_topic_arn, null)
}

output "prod_alerting_slack_notifier_lambda_name" {
  description = "Prod CloudWatch Slack notifier Lambda function name."
  value       = try(module.prod_alerting_slack_notifier[0].lambda_function_name, null)
}

output "prod_alerting_slack_webhook_secret_arn" {
  description = "Prod Slack webhook Secrets Manager secret ARN for monitoring alerts."
  value       = try(module.prod_alerting_slack_notifier[0].slack_webhook_secret_arn, null)
}

output "prod_cloudwatch_alert_alarm_names" {
  description = "Prod CloudWatch monitoring alert alarm names."
  value       = try(module.prod_alerting_slack_notifier[0].cloudwatch_alarm_names, [])
}

output "prod_opensearch_recovery_strategy" {
  description = "Prod OpenSearch recovery strategy. OpenSearch is treated as a derived index and rebuilt from source-of-truth data."
  value       = var.prod_opensearch_recovery_strategy
}

output "prod_opensearch_source_of_truth" {
  description = "Authoritative source used to rebuild Prod OpenSearch indexes."
  value       = var.prod_opensearch_source_of_truth
}

output "prod_external_dns_irsa_role_arn" {
  description = "Prod ExternalDNS IRSA role ARN."
  value       = try(aws_iam_role.prod_external_dns[0].arn, null)
}

output "prod_api_origin_domain_name" {
  description = "Stable Prod API origin domain used by CloudFront."
  value       = local.prod_edge_origin_domain_name
}

output "prod_karpenter_node_subnet_ids" {
  description = "Prod Karpenter node subnet IDs (karpenter.sh/discovery tagged)."
  value       = try(module.prod_vpc[0].prod_karpenter_node_subnet_ids, [])
}

output "prod_karpenter_controller_role_arn" {
  description = "Prod Karpenter controller IRSA role ARN. Referenced by gitops/argocd/prod/applications/karpenter-prod.yaml."
  value       = try(module.prod_karpenter[0].controller_role_arn, null)
}

output "prod_karpenter_node_role_name" {
  description = "Prod Karpenter node role name. Referenced by gitops/apps/prod/karpenter/ec2nodeclass.yaml."
  value       = try(module.prod_karpenter[0].node_role_name, null)
}

output "prod_karpenter_interruption_queue_name" {
  description = "Prod Karpenter interruption SQS queue name. Referenced by Karpenter settings.interruptionQueue."
  value       = try(module.prod_karpenter[0].interruption_queue_name, null)
}
