locals {
  prod_external_dns_enabled = var.enable_prod_external_dns && var.enable_prod_eks

  prod_external_dns_role_name = "${var.project_name}-prod-external-dns-irsa-role"

  prod_external_dns_hosted_zone_id_effective = local.prod_external_dns_enabled ? (
    var.prod_external_dns_hosted_zone_id != ""
    ? var.prod_external_dns_hosted_zone_id
    : data.aws_route53_zone.prod_external_dns[0].zone_id
  ) : ""
}

data "aws_route53_zone" "prod_external_dns" {
  count = local.prod_external_dns_enabled && var.prod_external_dns_hosted_zone_id == "" ? 1 : 0

  name         = var.prod_external_dns_hosted_zone_name
  private_zone = false
}

data "aws_iam_policy_document" "prod_external_dns_assume_role" {
  count = local.prod_external_dns_enabled ? 1 : 0

  statement {
    effect = "Allow"

    actions = [
      "sts:AssumeRoleWithWebIdentity",
    ]

    principals {
      type = "Federated"
      identifiers = [
        module.prod_eks[0].eks_oidc_provider_arn,
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.prod_eks[0].eks_oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.prod_eks[0].eks_oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${var.prod_external_dns_namespace}:${var.prod_external_dns_service_account_name}"]
    }
  }
}

data "aws_iam_policy_document" "prod_external_dns_route53" {
  count = local.prod_external_dns_enabled ? 1 : 0

  statement {
    sid    = "AllowChangeManagedHostedZoneRecords"
    effect = "Allow"

    actions = [
      "route53:ChangeResourceRecordSets",
    ]

    resources = [
      "arn:aws:route53:::hostedzone/${local.prod_external_dns_hosted_zone_id_effective}",
    ]
  }

  statement {
    sid    = "AllowReadRoute53State"
    effect = "Allow"

    actions = [
      "route53:ListHostedZones",
      "route53:ListResourceRecordSets",
      "route53:ListTagsForResource",
      "route53:GetChange",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role" "prod_external_dns" {
  count = local.prod_external_dns_enabled ? 1 : 0

  name               = local.prod_external_dns_role_name
  assume_role_policy = data.aws_iam_policy_document.prod_external_dns_assume_role[0].json

  tags = {
    Name        = local.prod_external_dns_role_name
    Project     = var.project_name
    Environment = "prod"
    ManagedBy   = "Terraform"
    Owner       = "team04"
    Component   = "external-dns"
  }
}

resource "aws_iam_policy" "prod_external_dns_route53" {
  count = local.prod_external_dns_enabled ? 1 : 0

  name        = "${var.project_name}-prod-external-dns-route53-policy"
  description = "Allow Prod ExternalDNS to manage Route53 records in the configured hosted zone."
  policy      = data.aws_iam_policy_document.prod_external_dns_route53[0].json

  tags = {
    Name        = "${var.project_name}-prod-external-dns-route53-policy"
    Project     = var.project_name
    Environment = "prod"
    ManagedBy   = "Terraform"
    Owner       = "team04"
    Component   = "external-dns"
  }
}

resource "aws_iam_role_policy_attachment" "prod_external_dns_route53" {
  count = local.prod_external_dns_enabled ? 1 : 0

  role       = aws_iam_role.prod_external_dns[0].name
  policy_arn = aws_iam_policy.prod_external_dns_route53[0].arn
}
