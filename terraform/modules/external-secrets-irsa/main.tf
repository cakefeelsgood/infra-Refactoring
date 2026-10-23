data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  tags = merge(
    var.common_tags,
    {
      Environment = var.environment
      ManagedBy   = "Terraform"
      Component   = "external-secrets-irsa"
    }
  )

  rds_managed_secret_arn_patterns = var.allow_rds_managed_secrets ? [
    "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:rds!db-*"
  ] : []

  allowed_secret_arns = distinct(concat(var.secret_arns, local.rds_managed_secret_arn_patterns))
}

data "aws_iam_policy_document" "assume_role" {
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
      values   = ["system:serviceaccount:${var.namespace}:${var.service_account_name}"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${local.name_prefix}-external-secrets-irsa-role"
  description        = "IRSA role for External Secrets Operator to read ${var.environment} runtime secrets"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-external-secrets-irsa-role"
    Role = "external-secrets-irsa"
  })
}

data "aws_iam_policy_document" "secrets_read" {
  statement {
    sid    = "AllowReadRuntimeSecrets"
    effect = "Allow"

    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
      "secretsmanager:ListSecretVersionIds"
    ]

    resources = local.allowed_secret_arns
  }
}

resource "aws_iam_policy" "this" {
  name        = "${local.name_prefix}-external-secrets-read-policy"
  description = "Allow External Secrets Operator to read ${var.environment} runtime secrets from AWS Secrets Manager"
  policy      = data.aws_iam_policy_document.secrets_read.json

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-external-secrets-read-policy"
    Role = "external-secrets-read"
  })
}

resource "aws_iam_role_policy_attachment" "this" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.this.arn
}
