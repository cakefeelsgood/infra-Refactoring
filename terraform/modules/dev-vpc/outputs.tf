output "dev_vpc_id" {
  description = "Dev VPC ID."
  value       = aws_vpc.this.id
}

output "dev_vpc_cidr" {
  description = "Dev VPC CIDR block."
  value       = aws_vpc.this.cidr_block
}

output "dev_public_subnet_ids" {
  description = "Dev public subnet IDs."
  value       = aws_subnet.public[*].id
}

output "dev_private_app_subnet_ids" {
  description = "Dev private app subnet IDs."
  value       = aws_subnet.private_app[*].id
}

output "dev_karpenter_node_subnet_ids" {
  description = "Dev Karpenter node subnet IDs."
  value       = aws_subnet.karpenter_node[*].id
}

output "dev_private_data_subnet_ids" {
  description = "Dev private data subnet IDs. The second subnet is reserved for future Multi-AZ data tier."
  value       = aws_subnet.private_data[*].id
}

output "dev_reserved_data_subnet_ids" {
  description = "Dev reserved data subnet IDs for future Multi-AZ data tier expansion."
  value = length(aws_subnet.private_data[*].id) > 1 ? slice(
    aws_subnet.private_data[*].id,
    1,
    length(aws_subnet.private_data[*].id)
  ) : []
}

output "dev_tgw_subnet_ids" {
  description = "Dev TGW attachment subnet IDs."
  value       = aws_subnet.tgw[*].id
}

output "dev_igw_id" {
  description = "Dev Internet Gateway ID."
  value       = aws_internet_gateway.this.id
}

output "dev_public_route_table_id" {
  description = "Dev public route table ID."
  value       = aws_route_table.public.id
}

output "dev_private_app_route_table_id" {
  description = "Dev private app route table ID."
  value       = aws_route_table.private_app.id
}

output "dev_private_data_route_table_id" {
  description = "Dev private data route table ID."
  value       = aws_route_table.private_data.id
}

output "dev_tgw_route_table_id" {
  description = "Dev TGW subnet route table ID."
  value       = aws_route_table.tgw.id
}
