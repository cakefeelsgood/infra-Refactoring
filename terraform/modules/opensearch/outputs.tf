output "domain_name" {
  description = "OpenSearch domain name."
  value       = aws_opensearch_domain.this.domain_name
}

output "domain_id" {
  description = "OpenSearch domain ID."
  value       = aws_opensearch_domain.this.domain_id
}

output "domain_arn" {
  description = "OpenSearch domain ARN."
  value       = aws_opensearch_domain.this.arn
}

output "endpoint" {
  description = "OpenSearch VPC endpoint."
  value       = aws_opensearch_domain.this.endpoint
}

output "dashboard_endpoint" {
  description = "OpenSearch Dashboards endpoint."
  value       = aws_opensearch_domain.this.dashboard_endpoint
}

output "engine_version" {
  description = "OpenSearch engine version."
  value       = aws_opensearch_domain.this.engine_version
}

output "vpc_options" {
  description = "OpenSearch VPC options."
  value       = aws_opensearch_domain.this.vpc_options
}
