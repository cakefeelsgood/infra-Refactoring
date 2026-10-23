output "cluster_name" {
  description = "EKS cluster name."
  value       = aws_eks_cluster.this.name
}

output "cluster_arn" {
  description = "EKS cluster ARN."
  value       = aws_eks_cluster.this.arn
}

output "cluster_endpoint" {
  description = "EKS cluster API endpoint."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded EKS cluster certificate authority data."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_version" {
  description = "EKS Kubernetes version."
  value       = aws_eks_cluster.this.version
}

output "cluster_status" {
  description = "EKS cluster status."
  value       = aws_eks_cluster.this.status
}

output "cluster_security_group_id" {
  description = "EKS cluster security group ID created by EKS."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "cluster_oidc_issuer_url" {
  description = "EKS cluster OIDC issuer URL."
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "eks_oidc_provider_arn" {
  description = "IAM OIDC Provider ARN for this EKS cluster."
  value       = try(aws_iam_openid_connect_provider.eks[0].arn, null)
}

output "eks_oidc_provider_url" {
  description = "IAM OIDC Provider URL without https://."
  value       = local.eks_oidc_provider_url
}

output "addon_versions" {
  description = "Installed EKS managed add-on versions."
  value = {
    for addon_name, addon in aws_eks_addon.this :
    addon_name => addon.addon_version
  }
}

output "cluster_admin_access_entry_arn" {
  description = "EKS access entry ARN for the configured primary cluster admin principal."
  value       = aws_eks_access_entry.cluster_admin.access_entry_arn
}

output "cluster_admin_additional_access_entry_arns" {
  description = "EKS access entry ARNs for configured additional cluster admin principals."
  value = {
    for principal_arn, access_entry in aws_eks_access_entry.cluster_admin_additional :
    principal_arn => access_entry.access_entry_arn
  }
}

output "ebs_csi_irsa_role_arn" {
  description = "IRSA role ARN for aws-ebs-csi-driver."
  value       = try(aws_iam_role.ebs_csi[0].arn, null)
}
