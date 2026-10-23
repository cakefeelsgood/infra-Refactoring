locals {
  dev_karpenter_enabled = var.enable_dev_karpenter && var.enable_dev_vpc && var.enable_dev_iam && var.enable_dev_eks
}

# AWS side of Karpenter. The controller, EC2NodeClass and NodePools are delivered by
# ArgoCD (gitops/argocd/dev/applications/karpenter-*.yaml, gitops/apps/dev/karpenter/).
# Role names and the queue name are deterministic and are referenced from those manifests.
module "dev_karpenter" {
  count  = local.dev_karpenter_enabled ? 1 : 0
  source = "../../modules/karpenter"

  project_name = var.project_name
  environment  = "dev"
  cluster_name = module.dev_eks[0].cluster_name

  eks_oidc_provider_arn = module.dev_eks[0].eks_oidc_provider_arn
  eks_oidc_provider_url = module.dev_eks[0].eks_oidc_provider_url

  cluster_security_group_id = module.dev_eks[0].cluster_security_group_id

  create_spot_service_linked_role = var.dev_karpenter_create_spot_service_linked_role

  common_tags = merge(local.common_tags, {
    Environment = "dev"
  })
}
