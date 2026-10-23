output "node_group_names" {
  description = "EKS managed node group names."
  value = {
    for key, node_group in aws_eks_node_group.this :
    key => node_group.node_group_name
  }
}

output "node_group_arns" {
  description = "EKS managed node group ARNs."
  value = {
    for key, node_group in aws_eks_node_group.this :
    key => node_group.arn
  }
}

output "node_group_statuses" {
  description = "EKS managed node group statuses."
  value = {
    for key, node_group in aws_eks_node_group.this :
    key => node_group.status
  }
}
