output "prod_vpc_id" {
  description = "Prod VPC ID."
  value       = aws_vpc.this.id
}

output "prod_vpc_cidr" {
  description = "Prod VPC CIDR block."
  value       = aws_vpc.this.cidr_block
}

output "prod_public_subnet_ids" {
  description = "Prod public subnet IDs."
  value       = aws_subnet.public[*].id
}

output "prod_private_app_subnet_ids" {
  description = "Prod private app subnet IDs."
  value       = aws_subnet.private_app[*].id
}

output "prod_karpenter_node_subnet_ids" {
  description = "Prod Karpenter node subnet IDs."
  value       = aws_subnet.karpenter_node[*].id
}

output "prod_private_data_subnet_ids" {
  description = "Prod private data subnet IDs."
  value       = aws_subnet.private_data[*].id
}

output "prod_tgw_subnet_ids" {
  description = "Prod TGW attachment subnet IDs."
  value       = aws_subnet.tgw[*].id
}

output "prod_igw_id" {
  description = "Prod Internet Gateway ID."
  value       = aws_internet_gateway.this.id
}

output "prod_public_route_table_id" {
  description = "Prod public route table ID."
  value       = aws_route_table.public.id
}

output "prod_private_app_route_table_id" {
  description = "Prod private app route table ID."
  value       = aws_route_table.private_app.id
}

output "prod_private_data_route_table_id" {
  description = "Prod private data route table ID."
  value       = aws_route_table.private_data.id
}

output "prod_tgw_route_table_id" {
  description = "Prod TGW subnet route table ID."
  value       = aws_route_table.tgw.id
}