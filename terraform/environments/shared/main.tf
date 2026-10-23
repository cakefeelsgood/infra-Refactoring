locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.env
    ManagedBy   = "terraform"
    Owner       = "team04"
  }
}

module "iam" {
  count  = var.enable_common_iam ? 1 : 0
  source = "../../modules/iam"

  project_name = var.project_name
  environment  = var.iam_resource_environment

  github_repository            = var.github_repository
  github_default_branch        = var.github_default_branch
  github_oidc_allowed_subjects = var.github_oidc_allowed_subjects

  create_github_oidc_provider = var.create_github_oidc_provider
  github_oidc_provider_arn    = var.github_oidc_provider_arn

  create_eks_oidc_provider = false
  enable_irsa_roles        = false

  ecr_repository_arns           = var.ecr_repository_arns
  raw_bucket_access_policy_arns = var.raw_bucket_access_policy_arns

  sqs_queue_arns                               = var.sqs_queue_arns
  enable_sqs_queue_policy_statements           = length(var.sqs_queue_arns) > 0
  opensearch_domain_arns                       = var.opensearch_domain_arns
  attach_lambda_raw_bucket_policy              = var.attach_lambda_raw_bucket_policy
  enable_lambda_collector_secrets_manager_read = var.enable_lambda_collector_secrets_manager_read

  common_tags = local.common_tags
}
