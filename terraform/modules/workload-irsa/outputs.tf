output "role_arns" {
  description = "Workload IRSA role ARNs keyed by service account logical name."
  value       = { for key, role in aws_iam_role.this : key => role.arn }
}

output "service_account_annotations" {
  description = "Kubernetes ServiceAccount annotation values for workload IRSA."
  value = {
    for key, sa in var.service_accounts :
    key => {
      namespace = sa.namespace
      name      = sa.name
      annotation = {
        "eks.amazonaws.com/role-arn" = aws_iam_role.this[key].arn
      }
    }
  }
}
