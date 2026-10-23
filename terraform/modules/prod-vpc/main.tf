locals {
  kubernetes_cluster_discovery_tags = var.eks_cluster_name == null ? {} : {
    "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"
  }
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.env}-vpc"
    Environment = var.env
    Role        = "prod-service-vpc"
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.env}-igw"
    Environment = var.env
  })
}

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, local.kubernetes_cluster_discovery_tags, {
    Name                     = "${var.project_name}-${var.env}-public-${count.index + 1}"
    Environment              = var.env
    Tier                     = "public"
    Role                     = "internet-facing-alb"
    "kubernetes.io/role/elb" = "1"
  })
}

resource "aws_subnet" "private_app" {
  count = length(var.private_app_subnet_cidrs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.private_app_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = merge(var.tags, local.kubernetes_cluster_discovery_tags, {
    Name                              = "${var.project_name}-${var.env}-private-app-${count.index + 1}"
    Environment                       = var.env
    Tier                              = "private-app"
    Role                              = "eks-worker-node"
    "kubernetes.io/role/internal-elb" = "1"
  })
}

# Karpenter nodes and their pods. Larger than private_app (/24) because VPC CNI Prefix
# Delegation reserves contiguous /28 blocks per node. Only these subnets carry the
# karpenter.sh/discovery tag, so EC2NodeClass never selects the /24 subnets.
resource "aws_subnet" "karpenter_node" {
  count = length(var.karpenter_node_subnet_cidrs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.karpenter_node_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = merge(var.tags, local.kubernetes_cluster_discovery_tags, {
    Name                     = "${var.project_name}-${var.env}-karpenter-node-${count.index + 1}"
    Environment              = var.env
    Tier                     = "private-app"
    Role                     = "eks-karpenter-node"
    "karpenter.sh/discovery" = var.eks_cluster_name
  })

  lifecycle {
    precondition {
      condition     = var.eks_cluster_name != null
      error_message = "karpenter_node_subnet_cidrs requires eks_cluster_name for the karpenter.sh/discovery tag."
    }
  }
}

resource "aws_subnet" "private_data" {
  count = length(var.private_data_subnet_cidrs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.private_data_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.env}-private-data-${count.index + 1}"
    Environment = var.env
    Tier        = "private-data"
    Role        = "rds-redis-opensearch"
  })
}

resource "aws_subnet" "tgw" {
  count = length(var.tgw_subnet_cidrs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.tgw_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.env}-tgw-${count.index + 1}"
    Environment = var.env
    Tier        = "tgw-attachment"
    Role        = "transit-gateway-attachment"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.env}-public-rt"
    Environment = var.env
    Tier        = "public"
  })
}

resource "aws_route" "public_to_igw" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private_app" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.env}-private-app-rt"
    Environment = var.env
    Tier        = "private-app"
  })
}

resource "aws_route" "private_app_default_to_tgw" {
  count = var.transit_gateway_id != null && var.private_app_default_route_target == "tgw" ? 1 : 0

  route_table_id         = aws_route_table.private_app.id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = var.transit_gateway_id
}

resource "aws_route" "private_app_to_network_vpc" {
  count = var.transit_gateway_id != null && var.enable_private_app_to_network_vpc_route ? 1 : 0

  route_table_id         = aws_route_table.private_app.id
  destination_cidr_block = "10.0.0.0/16"
  transit_gateway_id     = var.transit_gateway_id
}

resource "aws_route_table_association" "private_app" {
  count = length(aws_subnet.private_app)

  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.private_app.id
}

# Same route table as private_app: identical egress path and S3 gateway endpoint.
resource "aws_route_table_association" "karpenter_node" {
  count = length(aws_subnet.karpenter_node)

  subnet_id      = aws_subnet.karpenter_node[count.index].id
  route_table_id = aws_route_table.private_app.id
}

resource "aws_route_table" "private_data" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.env}-private-data-rt"
    Environment = var.env
    Tier        = "private-data"
  })
}

resource "aws_route_table_association" "private_data" {
  count = length(aws_subnet.private_data)

  subnet_id      = aws_subnet.private_data[count.index].id
  route_table_id = aws_route_table.private_data.id
}

resource "aws_route_table" "tgw" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name        = "${var.project_name}-${var.env}-tgw-rt"
    Environment = var.env
    Tier        = "tgw-attachment"
  })
}

resource "aws_route_table_association" "tgw" {
  count = length(aws_subnet.tgw)

  subnet_id      = aws_subnet.tgw[count.index].id
  route_table_id = aws_route_table.tgw.id
}
# NAT Gateway for EKS node internet access (image pull, external API)
