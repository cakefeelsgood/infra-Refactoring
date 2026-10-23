output "transit_gateway_id" {
  description = "Transit Gateway ID."
  value       = aws_ec2_transit_gateway.this.id
}

output "network_tgw_attachment_id" {
  description = "Network VPC TGW attachment ID."
  value       = aws_ec2_transit_gateway_vpc_attachment.network.id
}

output "prod_tgw_attachment_id" {
  description = "Prod VPC TGW attachment ID."
  value       = aws_ec2_transit_gateway_vpc_attachment.prod.id
}

output "dev_tgw_attachment_id" {
  description = "Dev VPC TGW attachment ID."
  value       = length(aws_ec2_transit_gateway_vpc_attachment.dev) > 0 ? aws_ec2_transit_gateway_vpc_attachment.dev[0].id : null
}

output "network_tgw_route_table_id" {
  description = "Network TGW route table ID."
  value       = aws_ec2_transit_gateway_route_table.network.id
}

output "prod_tgw_route_table_id" {
  description = "Prod TGW route table ID."
  value       = aws_ec2_transit_gateway_route_table.prod.id
}

output "dev_tgw_route_table_id" {
  description = "Dev TGW route table ID."
  value       = aws_ec2_transit_gateway_route_table.dev.id
}

output "tgw_attachment_ids" {
  description = "Transit Gateway attachment IDs by VPC role."
  value = {
    network = aws_ec2_transit_gateway_vpc_attachment.network.id
    prod    = aws_ec2_transit_gateway_vpc_attachment.prod.id
    dev     = length(aws_ec2_transit_gateway_vpc_attachment.dev) > 0 ? aws_ec2_transit_gateway_vpc_attachment.dev[0].id : null
  }
}

output "tgw_route_table_ids" {
  description = "Transit Gateway route table IDs by routing domain."
  value = {
    network = aws_ec2_transit_gateway_route_table.network.id
    prod    = aws_ec2_transit_gateway_route_table.prod.id
    dev     = aws_ec2_transit_gateway_route_table.dev.id
  }
}