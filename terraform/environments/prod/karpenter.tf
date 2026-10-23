locals {
  prod_karpenter_enabled = var.enable_prod_karpenter && var.enable_prod_vpc && var.enable_prod_eks
}

# AWS side of Karpenter. The controller, EC2NodeClass and NodePools are delivered by
# ArgoCD (gitops/argocd/prod/applications/karpenter-*.yaml, gitops/apps/prod/karpenter/).
# Role names and the queue name are deterministic and are referenced from those manifests.
module "prod_karpenter" {
  count  = local.prod_karpenter_enabled ? 1 : 0
  source = "../../modules/karpenter"

  project_name = var.project_name
  environment  = "prod"
  cluster_name = module.prod_eks[0].cluster_name

  eks_oidc_provider_arn = module.prod_eks[0].eks_oidc_provider_arn
  eks_oidc_provider_url = module.prod_eks[0].eks_oidc_provider_url

  cluster_security_group_id = module.prod_eks[0].cluster_security_group_id

  common_tags = local.prod_tags
}
