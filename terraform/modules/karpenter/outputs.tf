output "controller_role_arn" {
  description = "IRSA role ARN for the Karpenter controller ServiceAccount."
  value       = aws_iam_role.controller.arn
}

output "node_role_name" {
  description = "IAM role name used by Karpenter nodes (EC2NodeClass spec.role)."
  value       = aws_iam_role.node.name
}

output "node_role_arn" {
  description = "IAM role ARN used by Karpenter nodes."
  value       = aws_iam_role.node.arn
}

output "interruption_queue_name" {
  description = "SQS queue name for Karpenter settings.interruptionQueue."
  value       = aws_sqs_queue.interruption.name
}

output "interruption_queue_arn" {
  description = "SQS queue ARN for Karpenter interruption handling."
  value       = aws_sqs_queue.interruption.arn
}

output "discovery_tag" {
  description = "Tag that EC2NodeClass subnet and security group selectors match."
  value       = { "karpenter.sh/discovery" = var.cluster_name }
}
