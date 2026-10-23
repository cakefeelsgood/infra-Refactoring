data "aws_ec2_managed_prefix_list" "cloudfront_origin_facing" {
  count = var.create_service_sg && var.use_cloudfront_prefix_list ? 1 : 0

  name = "com.amazonaws.global.cloudfront.origin-facing"
}

locals {
  tags = merge(
    var.common_tags,
    {
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  )
}

resource "aws_security_group" "alb" {
  count = var.create_service_sg ? 1 : 0

  name        = "${var.name_prefix}-alb-sg"
  description = "Security group for internet-facing ALB"
  vpc_id      = var.vpc_id

  revoke_rules_on_delete = true

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-alb-sg"
    Role = "alb"
  })
}

resource "aws_security_group" "eks_node" {
  count = var.create_service_sg ? 1 : 0

  name        = "${var.name_prefix}-eks-node-sg"
  description = "Security group for EKS worker nodes"
  vpc_id      = var.vpc_id

  revoke_rules_on_delete = true

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-eks-node-sg"
    Role = "eks-node"
  })
}

resource "aws_security_group" "rds" {
  count = var.create_service_sg ? 1 : 0

  name        = "${var.name_prefix}-rds-sg"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = var.vpc_id

  revoke_rules_on_delete = true

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-rds-sg"
    Role = "rds"
  })
}

resource "aws_security_group" "redis" {
  count = var.create_service_sg ? 1 : 0

  name        = "${var.name_prefix}-redis-sg"
  description = "Security group for ElastiCache Redis"
  vpc_id      = var.vpc_id

  revoke_rules_on_delete = true

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-redis-sg"
    Role = "redis"
  })
}

resource "aws_security_group" "opensearch" {
  count = var.create_service_sg ? 1 : 0

  name        = "${var.name_prefix}-opensearch-sg"
  description = "Security group for OpenSearch"
  vpc_id      = var.vpc_id

  revoke_rules_on_delete = true

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-opensearch-sg"
    Role = "opensearch"
  })
}

resource "aws_security_group" "vpc_endpoint" {
  count = var.create_service_sg ? 1 : 0

  name        = "${var.name_prefix}-vpc-endpoint-sg"
  description = "Security group for VPC Interface Endpoints"
  vpc_id      = var.vpc_id

  revoke_rules_on_delete = true

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-vpc-endpoint-sg"
    Role = "vpc-endpoint"
  })
}

resource "aws_security_group" "openvpn" {
  count = var.create_openvpn_sg ? 1 : 0

  name        = "${var.name_prefix}-openvpn-sg"
  description = "Security group for OpenVPN admin access"
  vpc_id      = var.vpc_id

  revoke_rules_on_delete = true

  tags = merge(local.tags, {
    Name = "${var.name_prefix}-openvpn-sg"
    Role = "openvpn"
  })
}

# ALB inbound: CloudFront -> ALB HTTPS
resource "aws_security_group_rule" "alb_ingress_cloudfront_https" {
  count = var.create_service_sg && var.use_cloudfront_prefix_list ? 1 : 0

  type              = "ingress"
  security_group_id = aws_security_group.alb[0].id
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  prefix_list_ids   = [data.aws_ec2_managed_prefix_list.cloudfront_origin_facing[0].id]

  description = "Allow HTTPS from CloudFront origin-facing prefix list"
}

# Optional ALB inbound: restricted CIDR -> ALB HTTPS
resource "aws_security_group_rule" "alb_ingress_cidr_https" {
  count = var.create_service_sg && length(var.alb_allowed_cidr_blocks) > 0 ? 1 : 0

  type              = "ingress"
  security_group_id = aws_security_group.alb[0].id
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = var.alb_allowed_cidr_blocks

  description = "Allow HTTPS from restricted CIDR blocks"
}

# ALB outbound: ALB -> EKS Node app port
resource "aws_security_group_rule" "alb_egress_to_eks_node" {
  count = var.create_service_sg ? 1 : 0

  type                     = "egress"
  security_group_id        = aws_security_group.alb[0].id
  from_port                = var.app_port
  to_port                  = var.app_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_node[0].id

  description = "Allow ALB to send traffic to EKS nodes"
}

# EKS inbound: ALB -> EKS Node app port
resource "aws_security_group_rule" "eks_node_ingress_from_alb" {
  count = var.create_service_sg ? 1 : 0

  type                     = "ingress"
  security_group_id        = aws_security_group.eks_node[0].id
  from_port                = var.app_port
  to_port                  = var.app_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb[0].id

  description = "Allow app traffic from ALB"
}

# EKS internal communication
resource "aws_security_group_rule" "eks_node_ingress_self" {
  count = var.create_service_sg ? 1 : 0

  type              = "ingress"
  security_group_id = aws_security_group.eks_node[0].id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  self              = true

  description = "Allow internal communication between EKS nodes"
}

resource "aws_security_group_rule" "eks_node_egress_self" {
  count = var.create_service_sg ? 1 : 0

  type              = "egress"
  security_group_id = aws_security_group.eks_node[0].id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  self              = true

  description = "Allow internal communication between EKS nodes"
}

# EKS outbound: EKS Node -> RDS
resource "aws_security_group_rule" "eks_node_egress_to_rds" {
  count = var.create_service_sg ? 1 : 0

  type                     = "egress"
  security_group_id        = aws_security_group.eks_node[0].id
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.rds[0].id

  description = "Allow EKS nodes to access RDS PostgreSQL"
}

resource "aws_security_group_rule" "rds_ingress_from_eks_node" {
  count = var.create_service_sg ? 1 : 0

  type                     = "ingress"
  security_group_id        = aws_security_group.rds[0].id
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_node[0].id

  description = "Allow PostgreSQL from EKS nodes"
}

# EKS outbound: EKS Node -> Redis
resource "aws_security_group_rule" "eks_node_egress_to_redis" {
  count = var.create_service_sg ? 1 : 0

  type                     = "egress"
  security_group_id        = aws_security_group.eks_node[0].id
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.redis[0].id

  description = "Allow EKS nodes to access Redis"
}

resource "aws_security_group_rule" "redis_ingress_from_eks_node" {
  count = var.create_service_sg ? 1 : 0

  type                     = "ingress"
  security_group_id        = aws_security_group.redis[0].id
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_node[0].id

  description = "Allow Redis from EKS nodes"
}

# EKS outbound: EKS Node -> OpenSearch
resource "aws_security_group_rule" "eks_node_egress_to_opensearch" {
  count = var.create_service_sg ? 1 : 0

  type                     = "egress"
  security_group_id        = aws_security_group.eks_node[0].id
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.opensearch[0].id

  description = "Allow EKS nodes to access OpenSearch HTTPS"
}

resource "aws_security_group_rule" "opensearch_ingress_from_eks_node" {
  count = var.create_service_sg ? 1 : 0

  type                     = "ingress"
  security_group_id        = aws_security_group.opensearch[0].id
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_node[0].id

  description = "Allow OpenSearch HTTPS from EKS nodes"
}

# EKS outbound: EKS Node -> VPC Endpoint
resource "aws_security_group_rule" "eks_node_egress_to_vpc_endpoint" {
  count = var.create_service_sg ? 1 : 0

  type                     = "egress"
  security_group_id        = aws_security_group.eks_node[0].id
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.vpc_endpoint[0].id

  description = "Allow EKS nodes to access VPC Interface Endpoints"
}

resource "aws_security_group_rule" "vpc_endpoint_ingress_from_eks_node" {
  count = var.create_service_sg ? 1 : 0

  type                     = "ingress"
  security_group_id        = aws_security_group.vpc_endpoint[0].id
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.eks_node[0].id

  description = "Allow HTTPS from EKS nodes to VPC endpoints"
}

# EKS outbound: HTTPS egress through route table path such as TGW -> Network NAT
resource "aws_security_group_rule" "eks_node_egress_https_to_nat_path" {
  count = var.create_service_sg ? 1 : 0

  type              = "egress"
  security_group_id = aws_security_group.eks_node[0].id
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]

  description = "Allow limited HTTPS egress through NAT path"
}

# OpenVPN inbound: Admin CIDR only
resource "aws_security_group_rule" "openvpn_ingress_from_admin" {
  count = var.create_openvpn_sg && length(var.admin_cidr_blocks) > 0 ? 1 : 0

  type              = "ingress"
  security_group_id = aws_security_group.openvpn[0].id
  from_port         = var.openvpn_port
  to_port           = var.openvpn_port
  protocol          = var.openvpn_protocol
  cidr_blocks       = var.admin_cidr_blocks

  description = "Allow OpenVPN access from administrator CIDR blocks only"
}



resource "aws_security_group_rule" "openvpn_egress_all" {
  count = var.create_openvpn_sg ? 1 : 0

  type              = "egress"
  security_group_id = aws_security_group.openvpn[0].id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]

  description = "Allow OpenVPN outbound traffic"
}


# OpenVPN routed client CIDR -> Data Tier restricted admin access
resource "aws_security_group_rule" "rds_ingress_from_openvpn_clients" {
  count = var.create_service_sg && length(var.openvpn_client_cidr_blocks) > 0 ? 1 : 0

  type              = "ingress"
  security_group_id = aws_security_group.rds[0].id
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  cidr_blocks       = var.openvpn_client_cidr_blocks

  description = "Allow PostgreSQL from OpenVPN client CIDR"
}

resource "aws_security_group_rule" "redis_ingress_from_openvpn_clients" {
  count = var.create_service_sg && length(var.openvpn_client_cidr_blocks) > 0 ? 1 : 0

  type              = "ingress"
  security_group_id = aws_security_group.redis[0].id
  from_port         = 6379
  to_port           = 6379
  protocol          = "tcp"
  cidr_blocks       = var.openvpn_client_cidr_blocks

  description = "Allow Redis from OpenVPN client CIDR"
}

resource "aws_security_group_rule" "opensearch_ingress_from_openvpn_clients" {
  count = var.create_service_sg && length(var.openvpn_client_cidr_blocks) > 0 ? 1 : 0

  type              = "ingress"
  security_group_id = aws_security_group.opensearch[0].id
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = var.openvpn_client_cidr_blocks

  description = "Allow OpenSearch HTTPS from OpenVPN client CIDR"
}


# ==============================================================
# EKS Cluster SG (자동생성) -> Data 서비스 접근 허용
# 원인: EKS 노드 ENI에 실제 붙는 SG는 Terraform SG가 아닌
#       EKS가 자동 생성한 Cluster SG (sg-04fd7dd77b6fd278e)
# ==============================================================

variable "eks_cluster_sg_id" {
  description = "EKS Cluster auto-generated security group ID"
  type        = string
  default     = ""
}

variable "create_eks_cluster_sg_ingress_rules" {
  description = "Whether to create ingress rules from the EKS cluster auto-generated security group. Keep false for fresh apply until the cluster SG ID is known."
  type        = bool
  default     = false
}

resource "aws_security_group_rule" "rds_ingress_from_eks_cluster_sg" {
  count = var.create_service_sg && var.create_eks_cluster_sg_ingress_rules ? 1 : 0

  type                     = "ingress"
  security_group_id        = aws_security_group.rds[0].id
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = var.eks_cluster_sg_id

  description = "Allow PostgreSQL from EKS Cluster SG (auto-generated)"
}

resource "aws_security_group_rule" "redis_ingress_from_eks_cluster_sg" {
  count = var.create_service_sg && var.create_eks_cluster_sg_ingress_rules ? 1 : 0

  type                     = "ingress"
  security_group_id        = aws_security_group.redis[0].id
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = var.eks_cluster_sg_id

  description = "Allow Redis from EKS Cluster SG (auto-generated)"
}

resource "aws_security_group_rule" "opensearch_ingress_from_eks_cluster_sg" {
  count = var.create_service_sg && var.create_eks_cluster_sg_ingress_rules ? 1 : 0

  type                     = "ingress"
  security_group_id        = aws_security_group.opensearch[0].id
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = var.eks_cluster_sg_id

  description = "Allow OpenSearch HTTPS from EKS Cluster SG (auto-generated)"
}

# EKS Cluster 자동생성 SG → Data 서비스 접근 허용
# (노드 ENI에 실제 붙는 SG는 Terraform SG가 아닌 EKS Cluster SG)
