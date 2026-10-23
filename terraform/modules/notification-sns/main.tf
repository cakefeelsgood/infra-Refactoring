locals {
  topic_name = coalesce(
    var.topic_name,
    "${var.project_name}-${var.environment}-notification-topic"
  )

  tags = merge(
    var.common_tags,
    {
      Environment = var.environment
      ManagedBy   = "Terraform"
      Component   = "sns"
      Purpose     = "notification-publish"
    }
  )
}

resource "aws_sns_topic" "this" {
  name              = local.topic_name
  display_name      = var.display_name
  kms_master_key_id = var.kms_master_key_id

  tags = merge(local.tags, {
    Name = local.topic_name
  })
}
