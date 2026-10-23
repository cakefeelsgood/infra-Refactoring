data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

data "aws_region" "current" {}

locals {
  selected_ami_id = var.ami_id != "" ? var.ami_id : data.aws_ami.amazon_linux_2023.id

  client_profile_secret_name = var.client_profile_secret_name != "" ? var.client_profile_secret_name : "${var.name_prefix}-client-profile"

  public_endpoint = var.enable_eip ? aws_eip.this[0].public_ip : "OPENVPN_PUBLIC_ENDPOINT"

  tags = merge(
    var.common_tags,
    {
      Environment = var.environment
      ManagedBy   = "Terraform"
      Component   = "openvpn"
    }
  )

  route_push_lines = join("\n", [
    for cidr in var.route_cidrs : "push \"route ${cidrhost(cidr, 0)} ${cidrnetmask(cidr)}\""
  ])
}

resource "aws_iam_role" "this" {
  name = "${var.name_prefix}-openvpn-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-openvpn-role"
    Role = "openvpn-bootstrap"
  })
}

resource "aws_iam_role_policy" "client_profile_secret_write" {
  name = "${var.name_prefix}-openvpn-client-profile-secret-write"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteOpenVpnClientProfileSecret"
        Effect = "Allow"
        Action = [
          "secretsmanager:DescribeSecret",
          "secretsmanager:PutSecretValue"
        ]
        Resource = var.client_profile_secret_arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "this" {
  name = "${var.name_prefix}-openvpn-instance-profile"
  role = aws_iam_role.this.name

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-openvpn-instance-profile"
    Role = "openvpn-bootstrap"
  })
}

resource "aws_eip" "this" {
  count = var.enable_eip ? 1 : 0

  domain = "vpc"

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-openvpn-eip"
    Role = "admin-access"
  })
}

resource "aws_instance" "this" {
  ami                         = local.selected_ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [var.security_group_id]
  associate_public_ip_address = var.associate_public_ip_address
  source_dest_check           = false
  iam_instance_profile        = aws_iam_instance_profile.this.name

  user_data_replace_on_change = true

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    aws_region                = data.aws_region.current.name
    client_profile_secret_arn = var.client_profile_secret_arn
    public_endpoint           = local.public_endpoint
    openvpn_port              = var.openvpn_port
    openvpn_protocol          = var.openvpn_protocol
    vpn_cidr                  = var.vpn_cidr
    vpn_network               = cidrhost(var.vpn_cidr, 0)
    vpn_netmask               = cidrnetmask(var.vpn_cidr)
    route_cidrs               = join(" ", var.route_cidrs)
    route_push_lines          = local.route_push_lines
    enable_masquerade         = var.enable_masquerade
    client_name               = var.client_name
  })

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true
  }

  lifecycle {
    ignore_changes = [
      user_data
    ]
  }

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-openvpn"
    Role = "admin-access"
  })

  depends_on = [
    aws_iam_role_policy.client_profile_secret_write
  ]
}

resource "aws_eip_association" "this" {
  count = var.enable_eip ? 1 : 0

  instance_id   = aws_instance.this.id
  allocation_id = aws_eip.this[0].id
}
