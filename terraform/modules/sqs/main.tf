locals {
  name_prefix = "${var.project_name}-${var.environment}"

  tags = merge(
    var.common_tags,
    {
      Environment = var.environment
      ManagedBy   = "Terraform"
      Component   = "sqs"
    }
  )

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })
}

resource "aws_sqs_queue" "dlq" {
  name = var.dlq_name

  message_retention_seconds  = var.dlq_message_retention_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  delay_seconds              = var.delay_seconds
  max_message_size           = var.max_message_size
  sqs_managed_sse_enabled    = var.sqs_managed_sse_enabled

  tags = merge(local.tags, {
    Name = var.dlq_name
    Role = "dead-letter-queue"
  })
}

resource "aws_sqs_queue" "main" {
  name = var.queue_name

  message_retention_seconds  = var.message_retention_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  delay_seconds              = var.delay_seconds
  max_message_size           = var.max_message_size
  sqs_managed_sse_enabled    = var.sqs_managed_sse_enabled
  redrive_policy             = local.redrive_policy

  tags = merge(local.tags, {
    Name = var.queue_name
    Role = "main-queue"
  })
}
