output "db_instance_id" {
  description = "RDS DB instance ID."
  value       = aws_db_instance.this.id
}

output "db_instance_arn" {
  description = "RDS DB instance ARN."
  value       = aws_db_instance.this.arn
}

output "db_instance_identifier" {
  description = "RDS DB instance identifier."
  value       = aws_db_instance.this.identifier
}

output "db_instance_status" {
  description = "RDS DB instance status."
  value       = aws_db_instance.this.status
}

output "db_endpoint" {
  description = "RDS endpoint address."
  value       = aws_db_instance.this.address
}

output "db_port" {
  description = "RDS PostgreSQL port."
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Initial PostgreSQL database name."
  value       = aws_db_instance.this.db_name
}

output "db_subnet_group_name" {
  description = "RDS DB subnet group name."
  value       = aws_db_subnet_group.this.name
}

output "db_parameter_group_name" {
  description = "RDS DB parameter group name."
  value       = aws_db_parameter_group.this.name
}

output "master_user_secret_arn" {
  description = "Secrets Manager secret ARN managed by RDS for the master user password."
  value       = try(aws_db_instance.this.master_user_secret[0].secret_arn, null)
  sensitive   = true
}
