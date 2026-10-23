locals {
  m3_config_irsa_enabled = var.enable_dev_eks && var.enable_irsa_roles
}

data "aws_caller_identity" "m3_config_current" {}

locals {
  m3_config_oidc_provider_arn = local.m3_config_irsa_enabled ? (
    var.create_eks_oidc_provider ? module.dev_eks[0].eks_oidc_provider_arn : var.eks_oidc_provider_arn
  ) : ""
  m3_config_oidc_provider_url = local.m3_config_irsa_enabled ? (
    var.create_eks_oidc_provider ? module.dev_eks[0].eks_oidc_provider_url : replace(var.eks_oidc_issuer_url, "https://", "")
  ) : ""

  m3_config_namespace = "moment-dev"

  m3_config_backend_sa = "moment-dev-backend-api-sa"
  m3_config_ai_sa      = "moment-dev-ai-service-sa"
  m3_config_batch_sa   = "moment-dev-batch-job-sa"

  m3_config_account_id = data.aws_caller_identity.m3_config_current.account_id
  m3_config_region     = "ap-northeast-3"

  m3_config_profile_bucket = "moment-dev-profile-image-611058323802-ap-northeast-3"
  m3_config_raw_bucket     = "moment-dev-raw-data-611058323802-ap-northeast-3"
  m3_config_sqs_queue_name = "moment-dev-public-data-queue"
  m3_config_opensearch_arn = "arn:aws:es:ap-northeast-3:611058323802:domain/moment-dev-opensearch"
}

data "aws_iam_policy_document" "m3_config_backend_assume_role" {
  count = local.m3_config_irsa_enabled ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.m3_config_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.m3_config_oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${local.m3_config_namespace}:${local.m3_config_backend_sa}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.m3_config_oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "m3_config_ai_assume_role" {
  count = local.m3_config_irsa_enabled ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.m3_config_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.m3_config_oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${local.m3_config_namespace}:${local.m3_config_ai_sa}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.m3_config_oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "m3_config_batch_assume_role" {
  count = local.m3_config_irsa_enabled ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.m3_config_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.m3_config_oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${local.m3_config_namespace}:${local.m3_config_batch_sa}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.m3_config_oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "m3_config_backend_irsa" {
  count = local.m3_config_irsa_enabled ? 1 : 0

  name               = "moment-dev-backend-api-irsa-role"
  assume_role_policy = data.aws_iam_policy_document.m3_config_backend_assume_role[0].json

  tags = {
    Project     = "MoMent"
    Environment = "dev"
    ManagedBy   = "Terraform"
    Component   = "backend-api"
  }
}

resource "aws_iam_role" "m3_config_ai_irsa" {
  count = local.m3_config_irsa_enabled ? 1 : 0

  name               = "moment-dev-ai-service-irsa-role"
  assume_role_policy = data.aws_iam_policy_document.m3_config_ai_assume_role[0].json

  tags = {
    Project     = "MoMent"
    Environment = "dev"
    ManagedBy   = "Terraform"
    Component   = "ai-service"
  }
}

resource "aws_iam_role" "m3_config_batch_irsa" {
  count = local.m3_config_irsa_enabled ? 1 : 0

  name               = "moment-dev-batch-job-irsa-role"
  assume_role_policy = data.aws_iam_policy_document.m3_config_batch_assume_role[0].json

  tags = {
    Project     = "MoMent"
    Environment = "dev"
    ManagedBy   = "Terraform"
    Component   = "batch-job"
  }
}

data "aws_iam_policy_document" "m3_config_backend_policy" {
  count = local.m3_config_irsa_enabled ? 1 : 0

  statement {
    sid = "AllowProfileImageBucketAccess"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]

    resources = [
      "arn:aws:s3:::${local.m3_config_profile_bucket}",
      "arn:aws:s3:::${local.m3_config_profile_bucket}/*"
    ]
  }

  statement {
    sid = "AllowPublicDataQueueAccess"

    actions = [
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:SendMessage"
    ]

    resources = [
      "arn:aws:sqs:${local.m3_config_region}:${local.m3_config_account_id}:${local.m3_config_sqs_queue_name}"
    ]
  }
}

data "aws_iam_policy_document" "m3_config_ai_policy" {
  count = local.m3_config_irsa_enabled ? 1 : 0

  statement {
    sid = "AllowOpenSearchAccess"

    actions = [
      "es:ESHttpGet",
      "es:ESHttpPost",
      "es:ESHttpPut"
    ]

    resources = [
      local.m3_config_opensearch_arn,
      "${local.m3_config_opensearch_arn}/*"
    ]
  }
}

data "aws_iam_policy_document" "m3_config_batch_policy" {
  count = local.m3_config_irsa_enabled ? 1 : 0

  statement {
    sid = "AllowRawBucketAccess"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]

    resources = [
      "arn:aws:s3:::${local.m3_config_raw_bucket}",
      "arn:aws:s3:::${local.m3_config_raw_bucket}/*"
    ]
  }

  statement {
    sid = "AllowPublicDataQueueConsume"

    actions = [
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:ChangeMessageVisibility"
    ]

    resources = [
      "arn:aws:sqs:${local.m3_config_region}:${local.m3_config_account_id}:${local.m3_config_sqs_queue_name}"
    ]
  }

  statement {
    sid = "AllowOpenSearchAccess"

    actions = [
      "es:ESHttpGet",
      "es:ESHttpPost",
      "es:ESHttpPut"
    ]

    resources = [
      local.m3_config_opensearch_arn,
      "${local.m3_config_opensearch_arn}/*"
    ]
  }
}

resource "aws_iam_policy" "m3_config_backend_policy" {
  count = local.m3_config_irsa_enabled ? 1 : 0

  name   = "moment-dev-backend-api-irsa-policy"
  policy = data.aws_iam_policy_document.m3_config_backend_policy[0].json
}

resource "aws_iam_policy" "m3_config_ai_policy" {
  count = local.m3_config_irsa_enabled ? 1 : 0

  name   = "moment-dev-ai-service-irsa-policy"
  policy = data.aws_iam_policy_document.m3_config_ai_policy[0].json
}

resource "aws_iam_policy" "m3_config_batch_policy" {
  count = local.m3_config_irsa_enabled ? 1 : 0

  name   = "moment-dev-batch-job-irsa-policy"
  policy = data.aws_iam_policy_document.m3_config_batch_policy[0].json
}

resource "aws_iam_role_policy_attachment" "m3_config_backend_attach" {
  count = local.m3_config_irsa_enabled ? 1 : 0

  role       = aws_iam_role.m3_config_backend_irsa[0].name
  policy_arn = aws_iam_policy.m3_config_backend_policy[0].arn
}

resource "aws_iam_role_policy_attachment" "m3_config_ai_attach" {
  count = local.m3_config_irsa_enabled ? 1 : 0

  role       = aws_iam_role.m3_config_ai_irsa[0].name
  policy_arn = aws_iam_policy.m3_config_ai_policy[0].arn
}

resource "aws_iam_role_policy_attachment" "m3_config_batch_attach" {
  count = local.m3_config_irsa_enabled ? 1 : 0

  role       = aws_iam_role.m3_config_batch_irsa[0].name
  policy_arn = aws_iam_policy.m3_config_batch_policy[0].arn
}

output "dev_backend_api_irsa_role_arn" {
  value = local.m3_config_irsa_enabled ? aws_iam_role.m3_config_backend_irsa[0].arn : null
}

output "dev_ai_service_irsa_role_arn" {
  value = local.m3_config_irsa_enabled ? aws_iam_role.m3_config_ai_irsa[0].arn : null
}

output "dev_batch_job_irsa_role_arn" {
  value = local.m3_config_irsa_enabled ? aws_iam_role.m3_config_batch_irsa[0].arn : null
}
