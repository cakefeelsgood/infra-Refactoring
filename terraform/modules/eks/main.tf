terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  tags = merge(
    var.common_tags,
    {
      Environment = var.environment
      ManagedBy   = "Terraform"
      Component   = "eks"
    }
  )

  eks_oidc_issuer_url   = aws_eks_cluster.this.identity[0].oidc[0].issuer
  eks_oidc_provider_url = replace(local.eks_oidc_issuer_url, "https://", "")

  ebs_csi_irsa_enabled = var.create_eks_oidc_provider && var.enable_ebs_csi_irsa
}

# ── EKS Cluster ───────────────────────────────────────────────────────────────
# M2-EKS-01 scope:
# - Prod EKS Cluster
# - EKS Access Entry
# - EKS managed Add-ons
# - EKS OIDC Provider
#
# Explicitly out of scope:
# - aws_eks_node_group
# - launch template / autoscaling group
# - Helm releases
# - Kubernetes workloads / ingress

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = var.cluster_role_arn
  version  = var.kubernetes_version

  enabled_cluster_log_types = var.enabled_cluster_log_types

  bootstrap_self_managed_addons = false

  access_config {
    authentication_mode                         = var.authentication_mode
    bootstrap_cluster_creator_admin_permissions = var.bootstrap_cluster_creator_admin_permissions
  }

  vpc_config {
    subnet_ids              = var.subnet_ids
    security_group_ids      = var.cluster_security_group_ids
    endpoint_private_access = var.endpoint_private_access
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.public_access_cidrs
  }

  kubernetes_network_config {
    ip_family         = "ipv4"
    service_ipv4_cidr = var.service_ipv4_cidr
  }

  tags = merge(local.tags, {
    Name = var.cluster_name
    Role = "eks-cluster"
  })
}

# ── EKS Access Entry ──────────────────────────────────────────────────────────
# Use EKS API based access management instead of aws-auth ConfigMap.

resource "aws_eks_access_entry" "cluster_admin" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.cluster_admin_principal_arn
  type          = "STANDARD"

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-cluster-admin-access-entry"
    Role = "eks-access-entry"
  })
}

resource "aws_eks_access_policy_association" "cluster_admin" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.cluster_admin_principal_arn
  policy_arn    = var.cluster_admin_access_policy_arn

  access_scope {
    type = "cluster"
  }

  depends_on = [
    aws_eks_access_entry.cluster_admin
  ]
}

resource "aws_eks_access_entry" "cluster_admin_additional" {
  for_each = toset([
    for principal_arn in var.cluster_admin_additional_principal_arns :
    principal_arn
    if principal_arn != var.cluster_admin_principal_arn
  ])

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  type          = "STANDARD"

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-cluster-admin-access-entry-additional"
    Role = "eks-access-entry"
  })
}

resource "aws_eks_access_policy_association" "cluster_admin_additional" {
  for_each = toset([for principal_arn in var.cluster_admin_additional_principal_arns : principal_arn if principal_arn != var.cluster_admin_principal_arn])

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value
  policy_arn    = var.cluster_admin_access_policy_arn

  access_scope {
    type = "cluster"
  }
}

# ── EKS OIDC Provider ─────────────────────────────────────────────────────────

data "tls_certificate" "eks" {
  count = var.create_eks_oidc_provider ? 1 : 0

  url = local.eks_oidc_issuer_url
}

resource "aws_iam_openid_connect_provider" "eks" {
  count = var.create_eks_oidc_provider ? 1 : 0

  url             = local.eks_oidc_issuer_url
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks[0].certificates[0].sha1_fingerprint]

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-eks-oidc-provider"
    Role = "eks-oidc-provider"
  })
}

# ── EBS CSI Driver IRSA ───────────────────────────────────────────────────────
# This supports aws-ebs-csi-driver add-on without creating any EKS NodeGroup.

data "aws_iam_policy_document" "ebs_csi_assume_role" {
  count = local.ebs_csi_irsa_enabled ? 1 : 0

  statement {
    sid     = "AllowEksServiceAccountAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks[0].arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.eks_oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.eks_oidc_provider_url}:sub"
      values = [
        "system:serviceaccount:${var.ebs_csi_service_account_namespace}:${var.ebs_csi_service_account_name}"
      ]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  count = local.ebs_csi_irsa_enabled ? 1 : 0

  name               = "${local.name_prefix}-ebs-csi-irsa-role"
  description        = "IRSA role for aws-ebs-csi-driver add-on"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role[0].json

  tags = merge(local.tags, {
    Name              = "${local.name_prefix}-ebs-csi-irsa-role"
    Role              = "ebs-csi-irsa"
    KubernetesNS      = var.ebs_csi_service_account_namespace
    KubernetesSA      = var.ebs_csi_service_account_name
    KubernetesSubject = "system:serviceaccount:${var.ebs_csi_service_account_namespace}:${var.ebs_csi_service_account_name}"
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  count = local.ebs_csi_irsa_enabled ? 1 : 0

  role       = aws_iam_role.ebs_csi[0].name
  policy_arn = var.ebs_csi_policy_arn
}

# ── EKS Managed Add-ons ───────────────────────────────────────────────────────
# NodeGroup creation is intentionally excluded because M2-EKS-02 owns it.

resource "aws_eks_addon" "this" {
  for_each = var.addons

  cluster_name  = aws_eks_cluster.this.name
  addon_name    = each.key
  addon_version = each.value.addon_version

  resolve_conflicts_on_create = each.value.resolve_conflicts_on_create
  resolve_conflicts_on_update = each.value.resolve_conflicts_on_update

  # Previously missing: callers' configuration_values (vpc-cni enableNetworkPolicy, Prefix Delegation)
  # were silently dropped by the object type conversion.
  configuration_values = each.value.configuration_values

  # Keep passing service_account_role_arn on every update. An OVERWRITE update without it
  # removed the aws-node IRSA binding in the VPC CNI experiment (403 CrashLoop).
  service_account_role_arn = try(each.value.service_account_role_arn, null) != null ? each.value.service_account_role_arn : (
    each.key == "aws-ebs-csi-driver" && local.ebs_csi_irsa_enabled ? aws_iam_role.ebs_csi[0].arn : null
  )

  tags = merge(local.tags, {
    Name = "${var.cluster_name}-${each.key}"
    Role = "eks-addon"
  })

  depends_on = [
    aws_eks_access_policy_association.cluster_admin,
    aws_iam_role_policy_attachment.ebs_csi
  ]
}
