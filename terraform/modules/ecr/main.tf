# ── ECR Repositories ──────────────────────────────────────────────────────────
# Backend API / AI Service / Batch Job 컨테이너 이미지를 저장할 ECR Repository를 생성한다.

resource "aws_ecr_repository" "this" {
  for_each = var.repositories

  name                 = each.value.name
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = var.encryption_type
  }

  tags = merge(var.tags, {
    Name        = each.value.name
    Service     = each.key
    Description = each.value.description
  })
}

# ── ECR Lifecycle Policy ──────────────────────────────────────────────────────
# 최근 tagged image는 일정 개수만 유지하고, untagged image는 자동 정리한다.

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = var.repositories

  repository = aws_ecr_repository.this[each.key].name
  policy     = file("${path.module}/lifecycle-policy.json")
}