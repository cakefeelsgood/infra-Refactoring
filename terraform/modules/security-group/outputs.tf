output "alb_sg_id" {
  description = "ALB security group ID"
  value       = try(aws_security_group.alb[0].id, null)
}

output "eks_node_sg_id" {
  description = "EKS node security group ID"
  value       = try(aws_security_group.eks_node[0].id, null)
}

output "rds_sg_id" {
  description = "RDS security group ID"
  value       = try(aws_security_group.rds[0].id, null)
}

output "redis_sg_id" {
  description = "Redis security group ID"
  value       = try(aws_security_group.redis[0].id, null)
}

output "opensearch_sg_id" {
  description = "OpenSearch security group ID"
  value       = try(aws_security_group.opensearch[0].id, null)
}

output "vpc_endpoint_sg_id" {
  description = "VPC Endpoint security group ID"
  value       = try(aws_security_group.vpc_endpoint[0].id, null)
}

output "openvpn_sg_id" {
  description = "OpenVPN security group ID"
  value       = try(aws_security_group.openvpn[0].id, null)
}

output "service_security_group_ids" {
  description = "Service security group IDs"
  value = {
    alb          = try(aws_security_group.alb[0].id, null)
    eks_node     = try(aws_security_group.eks_node[0].id, null)
    rds          = try(aws_security_group.rds[0].id, null)
    redis        = try(aws_security_group.redis[0].id, null)
    opensearch   = try(aws_security_group.opensearch[0].id, null)
    vpc_endpoint = try(aws_security_group.vpc_endpoint[0].id, null)
  }
}
