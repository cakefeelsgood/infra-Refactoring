output "redis_replication_group_id" {
  description = "ElastiCache Redis replication group ID."
  value       = aws_elasticache_replication_group.this.id
}

output "redis_arn" {
  description = "ElastiCache Redis replication group ARN."
  value       = aws_elasticache_replication_group.this.arn
}

output "redis_primary_endpoint" {
  description = "Primary endpoint address for Redis."
  value       = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "redis_reader_endpoint" {
  description = "Reader endpoint address for Redis."
  value       = aws_elasticache_replication_group.this.reader_endpoint_address
}

output "redis_port" {
  description = "Redis port."
  value       = aws_elasticache_replication_group.this.port
}

output "redis_subnet_group_name" {
  description = "Redis subnet group name."
  value       = aws_elasticache_subnet_group.this.name
}
