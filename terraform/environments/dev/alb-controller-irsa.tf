data "aws_iam_policy_document" "dev_alb_controller_irsa_assume_role" {
  count = var.enable_dev_eks && var.enable_irsa_roles ? 1 : 0

  statement {
    sid     = "AllowAwsLoadBalancerControllerAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.dev_eks[0].eks_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.dev_eks[0].eks_oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${module.dev_eks[0].eks_oidc_provider_url}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "aws_iam_role" "dev_alb_controller_irsa" {
  count = var.enable_dev_eks && var.enable_irsa_roles ? 1 : 0

  name               = "${var.project_name}-dev-alb-controller-irsa-role"
  assume_role_policy = data.aws_iam_policy_document.dev_alb_controller_irsa_assume_role[0].json

  tags = merge(local.common_tags, {
    Environment       = "dev"
    Component         = "iam"
    KubernetesNS      = "kube-system"
    KubernetesSA      = "aws-load-balancer-controller"
    KubernetesSubject = "system:serviceaccount:kube-system:aws-load-balancer-controller"
  })
}

resource "aws_iam_role_policy_attachment" "dev_alb_controller_irsa_attach" {
  count = var.enable_dev_eks && var.enable_irsa_roles && var.enable_dev_iam ? 1 : 0

  role       = aws_iam_role.dev_alb_controller_irsa[0].name
  policy_arn = module.dev_iam[0].policy_arns["aws_load_balancer_controller"]
}
