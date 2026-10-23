output "project_name" {
  description = "Project name."
  value       = var.project_name
}

output "env" {
  description = "Terraform environment name."
  value       = var.env
}

output "shared_state_key" {
  description = "Shared Terraform backend state key."
  value       = "shared/terraform.tfstate"
}

output "iam_github_oidc_provider_arn" {
  description = "GitHub Actions OIDC Provider ARN."
  value       = try(module.iam[0].github_oidc_provider_arn, null)
}

output "iam_role_arns" {
  description = "Common IAM role ARNs."
  value       = try(module.iam[0].role_arns, {})
}

output "iam_policy_arns" {
  description = "Common IAM policy ARNs."
  value       = try(module.iam[0].policy_arns, {})
}

output "lambda_collector_role_arn" {
  description = "Lambda Collector IAM role ARN."
  value       = try(module.iam[0].lambda_collector_role_arn, null)
}

output "eks_cluster_role_arn" {
  description = "EKS cluster IAM role ARN."
  value       = try(module.iam[0].role_arns.eks_cluster, null)
}

output "eks_node_role_arn" {
  description = "EKS node IAM role ARN."
  value       = try(module.iam[0].role_arns.eks_node, null)
}
