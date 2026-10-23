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

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  tags = merge(
    var.common_tags,
    {
      Environment = var.environment
      ManagedBy   = "Terraform"
      Component   = "iam"
    }
  )

  github_oidc_url = "https://token.actions.githubusercontent.com"

  github_allowed_subjects = length(var.github_oidc_allowed_subjects) > 0 ? var.github_oidc_allowed_subjects : [
    "repo:${var.github_repository}:ref:refs/heads/${var.github_default_branch}"
  ]

  github_oidc_provider_arn = var.github_oidc_provider_arn != null ? var.github_oidc_provider_arn : try(aws_iam_openid_connect_provider.github[0].arn, null)

  eks_oidc_provider_arn = try(
    coalesce(var.eks_oidc_provider_arn, aws_iam_openid_connect_provider.eks[0].arn),
    null
  )

  eks_oidc_provider_url = var.eks_oidc_issuer_url != "" ? replace(var.eks_oidc_issuer_url, "https://", "") : var.eks_oidc_provider_url

  irsa_enabled = var.enable_irsa_roles && local.eks_oidc_provider_arn != null && local.eks_oidc_provider_url != ""

  enabled_irsa_service_accounts = local.irsa_enabled ? var.irsa_service_accounts : {}

  secrets_manager_resource_arns = [
    "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:${var.project_name}/${var.environment}/*",
    "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:${var.project_name}-${var.environment}-*"
  ]

  cloudwatch_logs_resource_arns = [
    "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/eks/${local.name_prefix}*",
    "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/eks/${local.name_prefix}*:*",
    "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.name_prefix}*",
    "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.name_prefix}*:*"
  ]

  raw_bucket_access_policy_arns = distinct(compact(concat(
    var.raw_bucket_access_policy_arn != null ? [var.raw_bucket_access_policy_arn] : [],
    var.raw_bucket_access_policy_arns
  )))

  raw_bucket_access_policy_additional_arns = length(local.raw_bucket_access_policy_arns) > 1 ? slice(
    local.raw_bucket_access_policy_arns,
    1,
    length(local.raw_bucket_access_policy_arns)
  ) : []

  raw_bucket_access_policy_attachment_map = merge(
    var.raw_bucket_access_policy_arn != null ? {
      primary = var.raw_bucket_access_policy_arn
    } : {},
    {
      for idx, policy_arn in var.raw_bucket_access_policy_arns :
      "list_${idx}" => policy_arn
    },
    var.raw_bucket_access_policy_arn_map
  )

  lambda_collector_extra_policy_enabled = var.enable_sqs_queue_policy_statements || var.enable_lambda_collector_secrets_manager_read

  github_actions_ecr_push_enabled = length(values(var.ecr_repository_arns)) > 0
}

# ── GitHub Actions OIDC ───────────────────────────────────────────────────────

data "tls_certificate" "github" {
  count = var.create_github_oidc_provider ? 1 : 0
  url   = local.github_oidc_url
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url             = local.github_oidc_url
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github[0].certificates[0].sha1_fingerprint]

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-github-actions-oidc-provider"
  })
}

data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    sid     = "AllowGitHubActionsOidcAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.github_allowed_subjects
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "${local.name_prefix}-github-actions-role"
  description        = "GitHub Actions OIDC role for MoMent CI/CD"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-github-actions-role"
  })
}

data "aws_iam_policy_document" "github_actions_ecr_push" {
  count = local.github_actions_ecr_push_enabled ? 1 : 0

  statement {
    sid    = "AllowEcrAuthorizationToken"
    effect = "Allow"

    actions = [
      "ecr:GetAuthorizationToken"
    ]

    resources = ["*"]
  }

  statement {
    sid    = "AllowEcrImagePushPull"
    effect = "Allow"

    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:ListImages",
      "ecr:PutImage",
      "ecr:UploadLayerPart"
    ]

    resources = values(var.ecr_repository_arns)
  }
}

resource "aws_iam_policy" "github_actions_ecr_push" {
  count = local.github_actions_ecr_push_enabled ? 1 : 0

  name        = "${local.name_prefix}-github-actions-ecr-push-policy"
  description = "Allow GitHub Actions to push and pull MoMent ECR images"
  policy      = data.aws_iam_policy_document.github_actions_ecr_push[0].json

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "github_actions_ecr_push" {
  count = local.github_actions_ecr_push_enabled ? 1 : 0

  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions_ecr_push[0].arn
}

# ── EKS Cluster / Node IAM Roles ──────────────────────────────────────────────

data "aws_iam_policy_document" "eks_cluster_assume_role" {
  statement {
    sid     = "AllowEksAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster" {
  name               = "${local.name_prefix}-eks-cluster-role"
  description        = "IAM role for EKS control plane"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_assume_role.json

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-eks-cluster-role"
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

data "aws_iam_policy_document" "eks_node_assume_role" {
  statement {
    sid     = "AllowEc2AssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_node" {
  name               = "${local.name_prefix}-eks-node-role"
  description        = "IAM role for EKS managed node groups"
  assume_role_policy = data.aws_iam_policy_document.eks_node_assume_role.json

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-eks-node-role"
  })
}

resource "aws_iam_role_policy_attachment" "eks_node_worker" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_node_cni" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_node_ecr_read_only" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# ── EKS OIDC Provider / IRSA Trust ────────────────────────────────────────────

data "tls_certificate" "eks" {
  count = var.create_eks_oidc_provider && var.eks_oidc_issuer_url != "" ? 1 : 0
  url   = var.eks_oidc_issuer_url
}

resource "aws_iam_openid_connect_provider" "eks" {
  count = var.create_eks_oidc_provider && var.eks_oidc_issuer_url != "" ? 1 : 0

  url             = var.eks_oidc_issuer_url
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks[0].certificates[0].sha1_fingerprint]

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-eks-oidc-provider"
  })
}

data "aws_iam_policy_document" "irsa_assume_role" {
  for_each = local.enabled_irsa_service_accounts

  statement {
    sid     = "AllowEksServiceAccountAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.eks_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.eks_oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.eks_oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${each.value.namespace}:${each.value.name}"]
    }
  }
}

resource "aws_iam_role" "irsa" {
  for_each = local.enabled_irsa_service_accounts

  name               = "${local.name_prefix}-${replace(each.key, "_", "-")}-irsa-role"
  description        = "IRSA role for ${each.value.namespace}/${each.value.name}"
  assume_role_policy = data.aws_iam_policy_document.irsa_assume_role[each.key].json

  tags = merge(local.tags, {
    Name              = "${local.name_prefix}-${replace(each.key, "_", "-")}-irsa-role"
    KubernetesNS      = each.value.namespace
    KubernetesSA      = each.value.name
    KubernetesSubject = "system:serviceaccount:${each.value.namespace}:${each.value.name}"
  })
}

# ── Workload IAM Policies ─────────────────────────────────────────────────────

resource "aws_iam_policy" "aws_load_balancer_controller" {
  name        = "${local.name_prefix}-aws-load-balancer-controller-policy"
  description = "IAM policy for AWS Load Balancer Controller"
  policy      = file("${path.module}/aws-load-balancer-controller-policy.json")

  tags = local.tags
}

data "aws_iam_policy_document" "backend_pod" {
  statement {
    sid    = "AllowSecretsManagerRead"
    effect = "Allow"

    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue"
    ]

    resources = local.secrets_manager_resource_arns
  }

  statement {
    sid    = "AllowCloudWatchLogsWrite"
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents"
    ]

    resources = local.cloudwatch_logs_resource_arns
  }

  dynamic "statement" {
    for_each = length(var.profile_image_bucket_arns) > 0 ? [1] : []

    content {
      sid    = "AllowProfileImageUpload"
      effect = "Allow"

      actions = [
        "s3:AbortMultipartUpload",
        "s3:PutObject"
      ]

      resources = [
        for bucket_arn in var.profile_image_bucket_arns :
        "${bucket_arn}/${trimsuffix(trimprefix(var.profile_image_object_key_prefix, "/"), "/")}/*"
      ]
    }
  }

  dynamic "statement" {
    for_each = length(var.notification_sns_topic_arns) > 0 ? [1] : []

    content {
      sid    = "AllowNotificationSnsPublish"
      effect = "Allow"

      actions = [
        "sns:Publish"
      ]

      resources = var.notification_sns_topic_arns
    }
  }
}

resource "aws_iam_policy" "backend_pod" {
  name        = "${local.name_prefix}-backend-pod-policy"
  description = "IAM policy for Backend API pod"
  policy      = data.aws_iam_policy_document.backend_pod.json

  tags = local.tags
}

data "aws_iam_policy_document" "batch_pod" {
  statement {
    sid    = "AllowCloudWatchLogsWrite"
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents"
    ]

    resources = local.cloudwatch_logs_resource_arns
  }

  dynamic "statement" {
    for_each = var.enable_sqs_queue_policy_statements ? [1] : []

    content {
      sid    = "AllowSqsConsume"
      effect = "Allow"

      actions = [
        "sqs:ChangeMessageVisibility",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes",
        "sqs:ReceiveMessage"
      ]

      resources = var.sqs_queue_arns
    }
  }
}

resource "aws_iam_policy" "batch_pod" {
  name        = "${local.name_prefix}-batch-pod-policy"
  description = "IAM policy for Batch Job pod"
  policy      = data.aws_iam_policy_document.batch_pod.json

  tags = local.tags
}

data "aws_iam_policy_document" "ai_service_pod" {
  statement {
    sid    = "AllowSecretsManagerRead"
    effect = "Allow"

    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue"
    ]

    resources = local.secrets_manager_resource_arns
  }

  statement {
    sid    = "AllowCloudWatchLogsWrite"
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents"
    ]

    resources = local.cloudwatch_logs_resource_arns
  }

  dynamic "statement" {
    for_each = length(var.opensearch_domain_arns) > 0 ? [1] : []

    content {
      sid    = "AllowOpenSearchAccess"
      effect = "Allow"

      actions = [
        "es:ESHttpDelete",
        "es:ESHttpGet",
        "es:ESHttpHead",
        "es:ESHttpPatch",
        "es:ESHttpPost",
        "es:ESHttpPut"
      ]

      resources = var.opensearch_domain_arns
    }
  }
}

resource "aws_iam_policy" "ai_service_pod" {
  name        = "${local.name_prefix}-ai-service-pod-policy"
  description = "IAM policy for AI Service pod"
  policy      = data.aws_iam_policy_document.ai_service_pod.json

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "irsa_alb_controller" {
  for_each = contains(keys(local.enabled_irsa_service_accounts), "aws_load_balancer_controller") ? {
    aws_load_balancer_controller = local.enabled_irsa_service_accounts["aws_load_balancer_controller"]
  } : {}

  role       = aws_iam_role.irsa[each.key].name
  policy_arn = aws_iam_policy.aws_load_balancer_controller.arn
}

resource "aws_iam_role_policy_attachment" "irsa_backend" {
  for_each = contains(keys(local.enabled_irsa_service_accounts), "backend") ? {
    backend = local.enabled_irsa_service_accounts["backend"]
  } : {}

  role       = aws_iam_role.irsa[each.key].name
  policy_arn = aws_iam_policy.backend_pod.arn
}

resource "aws_iam_role_policy_attachment" "irsa_batch_base" {
  for_each = contains(keys(local.enabled_irsa_service_accounts), "batch") ? {
    batch = local.enabled_irsa_service_accounts["batch"]
  } : {}

  role       = aws_iam_role.irsa[each.key].name
  policy_arn = aws_iam_policy.batch_pod.arn
}

resource "aws_iam_role_policy_attachment" "irsa_batch_raw_bucket" {
  for_each = contains(keys(local.enabled_irsa_service_accounts), "batch") ? local.raw_bucket_access_policy_attachment_map : {}

  role       = aws_iam_role.irsa["batch"].name
  policy_arn = each.value
}

resource "aws_iam_role_policy_attachment" "irsa_ai_service" {
  for_each = contains(keys(local.enabled_irsa_service_accounts), "ai_service") ? {
    ai_service = local.enabled_irsa_service_accounts["ai_service"]
  } : {}

  role       = aws_iam_role.irsa[each.key].name
  policy_arn = aws_iam_policy.ai_service_pod.arn
}

# ── Lambda Collector IAM Role ─────────────────────────────────────────────────

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    sid     = "AllowLambdaAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_collector" {
  name               = "${local.name_prefix}-lambda-collector-role"
  description        = "IAM role for Lambda Collector"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-lambda-collector-role"
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_collector.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_raw_bucket" {
  for_each = var.attach_lambda_raw_bucket_policy ? local.raw_bucket_access_policy_attachment_map : {}

  role       = aws_iam_role.lambda_collector.name
  policy_arn = each.value
}

data "aws_iam_policy_document" "lambda_collector_extra" {
  dynamic "statement" {
    for_each = var.enable_sqs_queue_policy_statements ? [1] : []

    content {
      sid    = "AllowSqsSend"
      effect = "Allow"

      actions = [
        "sqs:GetQueueAttributes",
        "sqs:SendMessage"
      ]

      resources = var.sqs_queue_arns
    }
  }

  dynamic "statement" {
    for_each = var.enable_lambda_collector_secrets_manager_read ? [1] : []

    content {
      sid    = "AllowLambdaCollectorSecretsManagerRead"
      effect = "Allow"

      actions = [
        "secretsmanager:DescribeSecret",
        "secretsmanager:GetSecretValue"
      ]

      resources = local.secrets_manager_resource_arns
    }
  }
}

resource "aws_iam_policy" "lambda_collector_extra" {
  count = local.lambda_collector_extra_policy_enabled ? 1 : 0

  name        = "${local.name_prefix}-lambda-collector-extra-policy"
  description = "Additional IAM policy for Lambda Collector"
  policy      = data.aws_iam_policy_document.lambda_collector_extra.json

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "lambda_collector_extra" {
  count = local.lambda_collector_extra_policy_enabled ? 1 : 0

  role       = aws_iam_role.lambda_collector.name
  policy_arn = aws_iam_policy.lambda_collector_extra[0].arn
}
