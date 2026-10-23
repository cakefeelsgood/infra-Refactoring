locals {
  prod_workload_irsa_service_accounts = {
    aws_load_balancer_controller = {
      namespace = "kube-system"
      name      = "aws-load-balancer-controller"
    }
    backend = {
      namespace = "moment-prod"
      name      = "moment-prod-backend-api-sa"
    }
    ai_service = {
      namespace = "moment-prod"
      name      = "moment-prod-ai-service-sa"
    }
    batch = {
      namespace = "moment-prod"
      name      = "moment-prod-batch-job-sa"
    }
  }

  prod_workload_irsa_policy_arns_by_service_account = {
    aws_load_balancer_controller = {
      aws_load_balancer_controller = module.prod_iam[0].policy_arns.aws_load_balancer_controller
    }

    backend = {
      backend_pod = module.prod_iam[0].policy_arns.backend_pod
    }

    ai_service = {
      ai_service_pod = module.prod_iam[0].policy_arns.ai_service_pod
    }

    batch = merge(
      {
        batch_pod = module.prod_iam[0].policy_arns.batch_pod
      },
      var.enable_prod_s3_raw_bucket ? {
        raw_bucket = module.prod_s3_raw_bucket[0].raw_bucket_access_policy_arn
      } : {}
    )
  }
}

module "prod_workload_irsa" {
  count  = var.enable_prod_workload_irsa && var.enable_prod_iam && var.enable_prod_eks ? 1 : 0
  source = "../../modules/workload-irsa"

  project_name = var.project_name
  environment  = "prod"

  eks_oidc_provider_arn = module.prod_eks[0].eks_oidc_provider_arn
  eks_oidc_provider_url = module.prod_eks[0].eks_oidc_provider_url

  service_accounts               = local.prod_workload_irsa_service_accounts
  policy_arns_by_service_account = local.prod_workload_irsa_policy_arns_by_service_account

  common_tags = local.prod_tags

  # Dependency ordering is handled by explicit input references above:
  # - module.prod_eks[0].eks_oidc_provider_arn / eks_oidc_provider_url
  # - module.prod_iam[0].policy_arns
  # - module.prod_s3_raw_bucket[0].raw_bucket_access_policy_arn when enabled
  #
  # Avoid broad module-level depends_on here. It pulls unrelated pending Prod
  # changes into controlled workload IRSA target plans.
}
