output "project_name" {
  description = "Project name."
  value       = var.project_name
}

output "env" {
  description = "Terraform environment name."
  value       = var.env
}

output "network_state_key" {
  description = "Network Terraform backend state key."
  value       = "network/terraform.tfstate"
}

output "network_vpc_id" {
  description = "Network VPC ID."
  value       = try(module.network_vpc[0].network_vpc_id, null)
}

output "network_vpc_cidr" {
  description = "Network VPC CIDR block."
  value       = try(module.network_vpc[0].network_vpc_cidr, null)
}

output "network_public_subnet_ids" {
  description = "Network public subnet IDs."
  value       = try(module.network_vpc[0].public_subnet_ids, [])
}

output "network_tgw_subnet_ids" {
  description = "Network TGW subnet IDs."
  value       = try(module.network_vpc[0].tgw_subnet_ids, [])
}

output "network_public_route_table_id" {
  description = "Network public route table ID."
  value       = try(module.network_vpc[0].public_route_table_id, null)
}

output "network_tgw_route_table_id" {
  description = "First Network TGW subnet route table ID kept for backward compatibility."
  value       = try(module.network_vpc[0].tgw_route_table_id, null)
}

output "network_tgw_route_table_ids" {
  description = "Network TGW subnet route table IDs by TGW subnet index."
  value       = try(module.network_vpc[0].tgw_route_table_ids, [])
}

output "network_tgw_route_table_id_map" {
  description = "Network TGW subnet route table IDs keyed by Availability Zone."
  value       = try(module.network_vpc[0].tgw_route_table_id_map, {})
}

output "network_nat_gateway_id" {
  description = "First Network NAT Gateway ID kept for backward compatibility."
  value       = try(module.network_vpc[0].nat_gateway_id, null)
}

output "network_nat_gateway_ids" {
  description = "Network NAT Gateway IDs by public subnet index."
  value       = try(module.network_vpc[0].nat_gateway_ids, [])
}

output "network_nat_gateway_id_map" {
  description = "Network NAT Gateway IDs keyed by Availability Zone."
  value       = try(module.network_vpc[0].nat_gateway_id_map, {})
}

output "network_openvpn_sg_id" {
  description = "Network OpenVPN security group ID."
  value       = try(module.network_security_group[0].openvpn_sg_id, null)
}

output "transit_gateway_id" {
  description = "Transit Gateway ID."
  value       = try(module.transit_gateway[0].transit_gateway_id, null)
}

output "tgw_attachment_ids" {
  description = "Transit Gateway attachment IDs by VPC role."
  value       = try(module.transit_gateway[0].tgw_attachment_ids, {})
}

output "tgw_route_table_ids" {
  description = "Transit Gateway route table IDs by routing domain."
  value       = try(module.transit_gateway[0].tgw_route_table_ids, {})
}

output "network_openvpn_instance_id" {
  description = "Network OpenVPN EC2 instance ID."
  value       = try(module.network_openvpn[0].instance_id, null)
}


output "network_openvpn_primary_network_interface_id" {
  description = "Network OpenVPN EC2 primary network interface ID."
  value       = try(module.network_openvpn[0].primary_network_interface_id, null)
}


output "network_openvpn_public_ip" {
  description = "Network OpenVPN public IP."
  value       = try(module.network_openvpn[0].public_ip, null)
}

output "network_openvpn_client_profile_secret_name" {
  description = "Secrets Manager secret name for generated OpenVPN client profile."
  value       = try(module.network_openvpn[0].client_profile_secret_name, null)
}
