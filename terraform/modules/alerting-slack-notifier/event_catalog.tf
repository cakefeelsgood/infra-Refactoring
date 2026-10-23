variable "rds_failover_event_source_ids" {
  description = "RDS DB instance identifiers to subscribe for failover events."
  type        = list(string)
  default     = []
}

variable "event_catalog_name_prefix" {
  description = "Name prefix for event catalog resources."
  type        = string
  default     = ""
}

locals {
  event_catalog_name_prefix = var.event_catalog_name_prefix != "" ? var.event_catalog_name_prefix : format(
    "%s-%s",
    lookup(var.common_tags, "Project", "moment"),
    lookup(var.common_tags, "Environment", "unknown")
  )

  event_catalog_tags = merge(var.common_tags, {
    Component = "alerting"
    Catalog   = "event-catalog"
  })
}

resource "aws_sns_topic_policy" "allow_database_event_publish" {
  arn = aws_sns_topic.alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowRdsEventsPublish"
        Effect = "Allow"
        Principal = {
          Service = "rds.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.alerts.arn
      },
      {
        Sid    = "AllowElastiCacheEventsPublish"
        Effect = "Allow"
        Principal = {
          Service = "elasticache.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.alerts.arn
      }
    ]
  })
}

resource "aws_db_event_subscription" "rds_failover" {
  count = length(var.rds_failover_event_source_ids) > 0 ? 1 : 0

  name             = "${local.event_catalog_name_prefix}-rds-failover-events"
  sns_topic        = aws_sns_topic.alerts.arn
  source_type      = "db-instance"
  source_ids       = var.rds_failover_event_source_ids
  event_categories = ["failover"]
  enabled          = true

  tags = local.event_catalog_tags
}
