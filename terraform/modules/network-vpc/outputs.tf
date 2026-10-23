output "network_vpc_id" {
  description = "Network VPC ID."
  value       = aws_vpc.this.id
}

output "network_vpc_cidr" {
  description = "Network VPC CIDR block."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs."
  value       = aws_subnet.public[*].id
}

output "tgw_subnet_ids" {
  description = "TGW attachment subnet IDs."
  value       = aws_subnet.tgw[*].id
}

output "nat_gateway_id" {
  description = "First NAT Gateway ID kept for backward compatibility. Prefer nat_gateway_ids or nat_gateway_id_map."
  value       = try(aws_nat_gateway.this[0].id, null)
}

output "nat_gateway_ids" {
  description = "NAT Gateway IDs by public subnet index."
  value       = aws_nat_gateway.this[*].id
}

output "nat_gateway_id_map" {
  description = "NAT Gateway IDs keyed by Availability Zone."
  value = var.enable_nat_gateway ? {
    for index, subnet in aws_subnet.public :
    subnet.availability_zone => aws_nat_gateway.this[index].id
  } : {}
}

output "nat_eip_id" {
  description = "First NAT Gateway Elastic IP ID kept for backward compatibility. Prefer nat_eip_ids."
  value       = try(aws_eip.nat[0].id, null)
}

output "nat_eip_ids" {
  description = "NAT Gateway Elastic IP IDs by public subnet index."
  value       = aws_eip.nat[*].id
}

output "igw_id" {
  description = "Internet Gateway ID."
  value       = aws_internet_gateway.this.id
}

output "public_route_table_id" {
  description = "Public route table ID."
  value       = aws_route_table.public.id
}

output "tgw_route_table_id" {
  description = "First TGW subnet route table ID kept for backward compatibility. Prefer tgw_route_table_ids or tgw_route_table_id_map."
  value       = aws_route_table.tgw[0].id
}

output "tgw_route_table_ids" {
  description = "TGW subnet route table IDs by TGW subnet index."
  value       = aws_route_table.tgw[*].id
}

output "tgw_route_table_id_map" {
  description = "TGW subnet route table IDs keyed by Availability Zone."
  value = {
    for index, subnet in aws_subnet.tgw :
    subnet.availability_zone => aws_route_table.tgw[index].id
  }
}
