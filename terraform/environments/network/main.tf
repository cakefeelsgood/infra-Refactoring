locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.env
    ManagedBy   = "terraform"
    Owner       = "team04"
  }

  openvpn_client_routes_enabled = (
    var.enable_openvpn &&
    var.enable_network_vpc &&
    var.enable_transit_gateway &&
    length(var.prod_tgw_subnet_ids) > 0 &&
    length(var.dev_tgw_subnet_ids) > 0
  )
}


locals {
  openvpn_client_profile_secret_name = var.openvpn_client_profile_secret_name != "" ? var.openvpn_client_profile_secret_name : "${var.project_name}/network/openvpn-client-profile"
}

resource "aws_secretsmanager_secret" "openvpn_client_profile" {
  count = (var.enable_openvpn || var.preserve_openvpn_client_profile_secret) ? 1 : 0

  name                    = local.openvpn_client_profile_secret_name
  description             = "OpenVPN client profile for MoMent Network VPC admin access"
  recovery_window_in_days = var.openvpn_client_profile_secret_recovery_window_in_days

  tags = merge(local.common_tags, {
    Environment = "network"
    ManagedBy   = "Terraform"
    Component   = "openvpn"
    Name        = local.openvpn_client_profile_secret_name
    Role        = "openvpn-client-profile"
  })
}

moved {
  from = module.network_openvpn[0].aws_secretsmanager_secret.client_profile
  to   = aws_secretsmanager_secret.openvpn_client_profile[0]
}

module "network_vpc" {
  count  = var.enable_network_vpc ? 1 : 0
  source = "../../modules/network-vpc"

  project_name = var.project_name
  env          = var.env
  vpc_cidr     = var.network_vpc_cidr

  availability_zones = [
    "${var.primary_region}a",
    "${var.primary_region}c"
  ]

  public_subnet_cidrs = var.network_public_subnet_cidrs
  tgw_subnet_cidrs    = var.network_tgw_subnet_cidrs
  enable_nat_gateway  = var.enable_network_nat_gateway

  tags = local.common_tags
}

module "network_security_group" {
  count  = var.enable_network_vpc ? 1 : 0
  source = "../../modules/security-group"

  name_prefix       = "${var.project_name}-network"
  environment       = "network"
  vpc_id            = module.network_vpc[0].network_vpc_id
  create_service_sg = false
  create_openvpn_sg = true

  admin_cidr_blocks = var.admin_cidr_blocks
  openvpn_port      = var.openvpn_port
  openvpn_protocol  = var.openvpn_protocol

  common_tags = local.common_tags
}

module "transit_gateway" {
  count = (
    var.enable_transit_gateway &&
    var.enable_network_vpc &&
    length(var.prod_tgw_subnet_ids) > 0
  ) ? 1 : 0

  source = "../../modules/transit-gateway"

  project_name = var.project_name
  env          = var.env

  network_vpc_id                = module.network_vpc[0].network_vpc_id
  network_vpc_cidr              = module.network_vpc[0].network_vpc_cidr
  network_tgw_subnet_ids        = module.network_vpc[0].tgw_subnet_ids
  network_public_route_table_id = module.network_vpc[0].public_route_table_id

  openvpn_vpn_cidr             = var.openvpn_vpn_cidr
  enable_openvpn_client_routes = local.openvpn_client_routes_enabled

  prod_vpc_id                            = var.prod_vpc_id
  prod_vpc_cidr                          = var.prod_vpc_cidr
  prod_tgw_subnet_ids                    = var.prod_tgw_subnet_ids
  prod_private_app_route_table_id        = var.prod_private_app_route_table_id
  prod_private_data_route_table_id       = var.prod_private_data_route_table_id
  enable_prod_private_app_default_to_tgw = var.enable_prod_private_app_default_to_tgw

  dev_vpc_id                            = var.dev_vpc_id
  dev_vpc_cidr                          = var.dev_vpc_cidr
  dev_tgw_subnet_ids                    = var.dev_tgw_subnet_ids
  dev_private_app_route_table_id        = var.dev_private_app_route_table_id
  dev_private_data_route_table_id       = var.dev_private_data_route_table_id
  enable_dev_private_app_default_to_tgw = var.enable_dev_private_app_default_to_tgw

  tags = local.common_tags
}

module "network_openvpn" {
  count = (
    var.enable_openvpn &&
    var.enable_network_vpc &&
    var.enable_transit_gateway
  ) ? 1 : 0

  source = "../../modules/openvpn"

  name_prefix = "${var.project_name}-network"
  environment = "network"

  subnet_id         = module.network_vpc[0].public_subnet_ids[0]
  security_group_id = module.network_security_group[0].openvpn_sg_id

  ami_id        = var.openvpn_ami_id
  instance_type = var.openvpn_instance_type

  enable_eip                                    = var.openvpn_enable_eip
  openvpn_port                                  = var.openvpn_port
  openvpn_protocol                              = var.openvpn_protocol
  vpn_cidr                                      = var.openvpn_vpn_cidr
  route_cidrs                                   = [var.dev_vpc_cidr, var.prod_vpc_cidr]
  enable_masquerade                             = var.openvpn_enable_masquerade
  client_name                                   = var.openvpn_client_name
  client_profile_secret_name                    = local.openvpn_client_profile_secret_name
  client_profile_secret_arn                     = aws_secretsmanager_secret.openvpn_client_profile[0].arn
  client_profile_secret_recovery_window_in_days = var.openvpn_client_profile_secret_recovery_window_in_days
  root_volume_size                              = var.openvpn_root_volume_size

  common_tags = local.common_tags

}

resource "aws_route" "network_tgw_to_openvpn_clients" {
  count = local.openvpn_client_routes_enabled ? length(var.network_tgw_subnet_cidrs) : 0

  route_table_id         = module.network_vpc[0].tgw_route_table_ids[count.index]
  destination_cidr_block = var.openvpn_vpn_cidr
  network_interface_id   = module.network_openvpn[0].primary_network_interface_id

  lifecycle {
    precondition {
      condition = (
        var.dev_private_app_route_table_id != "" &&
        var.prod_private_app_route_table_id != "" &&
        var.dev_private_data_route_table_id != "" &&
        var.prod_private_data_route_table_id != ""
      )
      error_message = "OpenVPN routed Data Tier access requires dev/prod private app and private data route table IDs."
    }
  }

  depends_on = [
    module.network_openvpn
  ]
}
