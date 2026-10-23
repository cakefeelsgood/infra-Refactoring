output "github_oidc_provider_arn" {
  description = "GitHub Actions OIDC Provider ARN"
  value       = local.github_oidc_provider_arn
}

output "eks_oidc_provider_arn" {
  description = "EKS OIDC Provider ARN when configured"
  value       = local.eks_oidc_provider_arn
}

output "role_arns" {
  description = "IAM role ARNs"
  value = {
    github_actions   = aws_iam_role.github_actions.arn
    eks_cluster      = aws_iam_role.eks_cluster.arn
    eks_node         = aws_iam_role.eks_node.arn
    lambda_collector = aws_iam_role.lambda_collector.arn
    irsa             = { for key, role in aws_iam_role.irsa : key => role.arn }
  }
}

output "policy_arns" {
  description = "IAM policy ARNs"
  value = {
    github_actions_ecr_push      = local.github_actions_ecr_push_enabled ? aws_iam_policy.github_actions_ecr_push[0].arn : null
    aws_load_balancer_controller = aws_iam_policy.aws_load_balancer_controller.arn
    backend_pod                  = aws_iam_policy.backend_pod.arn
    batch_pod                    = aws_iam_policy.batch_pod.arn
    ai_service_pod               = aws_iam_policy.ai_service_pod.arn
    lambda_collector_extra       = try(aws_iam_policy.lambda_collector_extra[0].arn, null)
  }
}

output "irsa_enabled" {
  description = "Whether IRSA roles are currently enabled"
  value       = local.irsa_enabled
}

output "service_account_annotations" {
  description = "Kubernetes ServiceAccount annotation values for IRSA"
  value = {
    for key, sa in var.irsa_service_accounts :
    key => {
      namespace = sa.namespace
      name      = sa.name
      annotation = contains(keys(aws_iam_role.irsa), key) ? {
        "eks.amazonaws.com/role-arn" = aws_iam_role.irsa[key].arn
      } : null
    }
  }
}


output "lambda_collector_role_arn" {
  description = "Lambda Collector IAM role ARN."
  value       = aws_iam_role.lambda_collector.arn
}

output "eks_cluster_role_arn" {
  description = "EKS cluster IAM role ARN."
  value       = aws_iam_role.eks_cluster.arn
}

output "eks_node_role_arn" {
  description = "EKS node IAM role ARN."
  value       = aws_iam_role.eks_node.arn
}
