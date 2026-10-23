output "repository_names" {
  description = "ECR Repository 이름 목록."
  value = {
    for key, repository in aws_ecr_repository.this :
    key => repository.name
  }
}

output "repository_urls" {
  description = "ECR Repository URL 목록."
  value = {
    for key, repository in aws_ecr_repository.this :
    key => repository.repository_url
  }
}

output "repository_arns" {
  description = "ECR Repository ARN 목록."
  value = {
    for key, repository in aws_ecr_repository.this :
    key => repository.arn
  }
}

output "backend_repository_url" {
  description = "Backend API ECR Repository URL."
  value       = aws_ecr_repository.this["backend"].repository_url
}

output "ai_service_repository_url" {
  description = "AI Service ECR Repository URL."
  value       = aws_ecr_repository.this["ai-service"].repository_url
}

output "batch_repository_url" {
  description = "Batch Job ECR Repository URL."
  value       = aws_ecr_repository.this["batch"].repository_url
}