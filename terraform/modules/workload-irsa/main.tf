locals {
  name_prefix = "${var.project_name}-${var.environment}"

  tags = merge(
    var.common_tags,
    {
      Environment = var.environment
      ManagedBy   = "Terraform"
      Component   = "workload-irsa"
    }
  )

  policy_attachment_items = flatten([
    for role_key, policy_arns in var.policy_arns_by_service_account : [
      for policy_key, policy_arn in policy_arns : {
        key        = "${role_key}-${policy_key}"
        role_key   = role_key
        policy_arn = policy_arn
      }
      if contains(keys(var.service_accounts), role_key)
    ]
  ])

  policy_attachments = {
    for item in local.policy_attachment_items : item.key => item
  }
}

data "aws_iam_policy_document" "assume_role" {
  for_each = var.service_accounts

  statement {
    sid     = "AllowEksServiceAccountAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.eks_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.eks_oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.eks_oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${each.value.namespace}:${each.value.name}"]
    }
  }
}

resource "aws_iam_role" "this" {
  for_each = var.service_accounts

  name               = "${local.name_prefix}-${replace(each.key, "_", "-")}-irsa-role"
  description        = "IRSA role for ${var.environment} ${each.value.namespace}/${each.value.name}"
  assume_role_policy = data.aws_iam_policy_document.assume_role[each.key].json

  tags = merge(local.tags, {
    Name              = "${local.name_prefix}-${replace(each.key, "_", "-")}-irsa-role"
    Role              = "workload-irsa"
    KubernetesNS      = each.value.namespace
    KubernetesSA      = each.value.name
    KubernetesSubject = "system:serviceaccount:${each.value.namespace}:${each.value.name}"
  })
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each = local.policy_attachments

  role       = aws_iam_role.this[each.value.role_key].name
  policy_arn = each.value.policy_arn
}
