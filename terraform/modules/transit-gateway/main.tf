resource "aws_ec2_transit_gateway" "this" {
  description = "MoMent ${var.env} Transit Gateway for Network, Prod, and Dev VPC routing"

  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  auto_accept_shared_attachments  = "disable"

  dns_support      = "enable"
  vpn_ecmp_support = "enable"

  tags = merge(var.tags, {
    Name  = "${var.project_name}-${var.env}-tgw"
    Role  = "multi-vpc-routing-hub"
    Issue = "M2-NET-02"
  })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "network" {
  vpc_id             = var.network_vpc_id
  subnet_ids         = var.network_tgw_subnet_ids
  transit_gateway_id = aws_ec2_transit_gateway.this.id

  dns_support = "enable"

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = merge(var.tags, {
    Name  = "${var.project_name}-${var.env}-network-tgw-attachment"
    Role  = "network-hub-attachment"
    Issue = "M2-NET-02"
  })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "prod" {
  vpc_id             = var.prod_vpc_id
  subnet_ids         = var.prod_tgw_subnet_ids
  transit_gateway_id = aws_ec2_transit_gateway.this.id

  dns_support = "enable"

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = merge(var.tags, {
    Name  = "${var.project_name}-prod-tgw-attachment"
    Role  = "prod-service-attachment"
    Issue = "M2-NET-02"
  })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "dev" {
  count              = var.dev_vpc_id != "" && var.dev_vpc_id != null ? 1 : 0
  vpc_id             = var.dev_vpc_id
  subnet_ids         = var.dev_tgw_subnet_ids
  transit_gateway_id = aws_ec2_transit_gateway.this.id

  dns_support = "enable"

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = merge(var.tags, {
    Name  = "${var.project_name}-dev-tgw-attachment"
    Role  = "dev-service-attachment"
    Issue = "M2-NET-02"
  })
}

resource "aws_ec2_transit_gateway_route_table" "network" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id

  tags = merge(var.tags, {
    Name  = "${var.project_name}-${var.env}-tgw-rt-network"
    Role  = "network-hub-routing"
    Issue = "M2-NET-02"
  })
}

resource "aws_ec2_transit_gateway_route_table" "prod" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id

  tags = merge(var.tags, {
    Name  = "${var.project_name}-${var.env}-tgw-rt-prod"
    Role  = "prod-routing"
    Issue = "M2-NET-02"
  })
}

resource "aws_ec2_transit_gateway_route_table" "dev" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id

  tags = merge(var.tags, {
    Name  = "${var.project_name}-${var.env}-tgw-rt-dev"
    Role  = "dev-routing"
    Issue = "M2-NET-02"
  })
}

resource "aws_ec2_transit_gateway_route_table_association" "network" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.network.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.network.id
}

resource "aws_ec2_transit_gateway_route_table_association" "prod" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.prod.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.prod.id
}

resource "aws_ec2_transit_gateway_route_table_association" "dev" {
  count                          = var.dev_vpc_id != "" && var.dev_vpc_id != null ? 1 : 0
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.dev[0].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.dev.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "network_from_prod" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.prod.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.network.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "network_from_dev" {
  count                          = var.dev_vpc_id != "" && var.dev_vpc_id != null ? 1 : 0
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.dev[0].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.network.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "prod_from_network" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.network.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.prod.id
}

resource "aws_ec2_transit_gateway_route_table_propagation" "dev_from_network" {
  count                          = var.dev_vpc_id != "" && var.dev_vpc_id != null ? 1 : 0
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.network.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.dev.id
}

resource "aws_ec2_transit_gateway_route" "prod_default_to_network" {
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.network.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.prod.id
}

resource "aws_ec2_transit_gateway_route" "dev_default_to_network" {
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.network.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.dev.id
}

resource "aws_ec2_transit_gateway_route" "prod_to_openvpn_clients" {
  count = var.enable_openvpn_client_routes ? 1 : 0

  destination_cidr_block         = var.openvpn_vpn_cidr
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.network.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.prod.id
}

resource "aws_ec2_transit_gateway_route" "dev_to_openvpn_clients" {
  count = var.enable_openvpn_client_routes ? 1 : 0

  destination_cidr_block         = var.openvpn_vpn_cidr
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.network.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.dev.id
}

resource "aws_ec2_transit_gateway_route" "prod_to_dev_blackhole" {
  destination_cidr_block         = var.dev_vpc_cidr
  blackhole                      = true
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.prod.id
}

resource "aws_ec2_transit_gateway_route" "dev_to_prod_blackhole" {
  destination_cidr_block         = var.prod_vpc_cidr
  blackhole                      = true
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.dev.id
}

resource "aws_route" "network_public_to_prod_vpc" {
  route_table_id         = var.network_public_route_table_id
  destination_cidr_block = var.prod_vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [
    aws_ec2_transit_gateway_vpc_attachment.network,
    aws_ec2_transit_gateway_vpc_attachment.prod
  ]
}

resource "aws_route" "network_public_to_dev_vpc" {
  count                  = var.dev_vpc_id != "" && var.dev_vpc_id != null ? 1 : 0
  route_table_id         = var.network_public_route_table_id
  destination_cidr_block = var.dev_vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [
    aws_ec2_transit_gateway_vpc_attachment.network,
    aws_ec2_transit_gateway_vpc_attachment.dev
  ]
}

resource "aws_route" "prod_private_app_default_to_tgw" {
  count = var.enable_prod_private_app_default_to_tgw && var.prod_private_app_route_table_id != "" ? 1 : 0

  route_table_id         = var.prod_private_app_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [
    aws_ec2_transit_gateway_vpc_attachment.prod
  ]
}

resource "aws_route" "prod_private_app_to_network_vpc" {
  route_table_id         = var.prod_private_app_route_table_id
  destination_cidr_block = var.network_vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [
    aws_ec2_transit_gateway_vpc_attachment.prod
  ]
}

resource "aws_route" "dev_private_app_default_to_tgw" {
  count                  = var.enable_dev_private_app_default_to_tgw && var.dev_vpc_id != "" && var.dev_vpc_id != null ? 1 : 0
  route_table_id         = var.dev_private_app_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [
    aws_ec2_transit_gateway_vpc_attachment.dev
  ]
}

resource "aws_route" "dev_private_app_to_network_vpc" {
  count                  = var.dev_vpc_id != "" && var.dev_vpc_id != null ? 1 : 0
  route_table_id         = var.dev_private_app_route_table_id
  destination_cidr_block = var.network_vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [
    aws_ec2_transit_gateway_vpc_attachment.dev
  ]
}

resource "aws_route" "prod_private_data_to_openvpn_clients" {
  count = var.enable_openvpn_client_routes && var.prod_private_data_route_table_id != "" ? 1 : 0

  route_table_id         = var.prod_private_data_route_table_id
  destination_cidr_block = var.openvpn_vpn_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [
    aws_ec2_transit_gateway_vpc_attachment.prod
  ]
}

resource "aws_route" "dev_private_data_to_openvpn_clients" {
  count = var.enable_openvpn_client_routes && var.dev_private_data_route_table_id != "" ? 1 : 0

  route_table_id         = var.dev_private_data_route_table_id
  destination_cidr_block = var.openvpn_vpn_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [
    aws_ec2_transit_gateway_vpc_attachment.dev
  ]
}