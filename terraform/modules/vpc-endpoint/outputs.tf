output "s3_gateway_endpoint_id" {
  description = "S3 Gateway VPC Endpoint ID"
  value       = aws_vpc_endpoint.s3.id
}

output "interface_endpoint_ids" {
  description = "Interface VPC Endpoint IDs"
  value = {
    for service, endpoint in aws_vpc_endpoint.interface :
    service => endpoint.id
  }
}

output "interface_endpoint_dns_entries" {
  description = "Interface VPC Endpoint DNS entries"
  value = {
    for service, endpoint in aws_vpc_endpoint.interface :
    service => endpoint.dns_entry
  }
}