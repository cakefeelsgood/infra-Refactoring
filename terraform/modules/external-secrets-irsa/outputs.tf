output "role_arn" {
  description = "External Secrets Operator IRSA role ARN."
  value       = aws_iam_role.this.arn
}

output "policy_arn" {
  description = "External Secrets Operator read policy ARN."
  value       = aws_iam_policy.this.arn
}
