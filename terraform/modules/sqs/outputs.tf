output "queue_name" {
  description = "SQS main queue name."
  value       = aws_sqs_queue.main.name
}

output "queue_url" {
  description = "SQS main queue URL."
  value       = aws_sqs_queue.main.url
}

output "queue_arn" {
  description = "SQS main queue ARN."
  value       = aws_sqs_queue.main.arn
}

output "dlq_name" {
  description = "SQS dead-letter queue name."
  value       = aws_sqs_queue.dlq.name
}

output "dlq_url" {
  description = "SQS dead-letter queue URL."
  value       = aws_sqs_queue.dlq.url
}

output "dlq_arn" {
  description = "SQS dead-letter queue ARN."
  value       = aws_sqs_queue.dlq.arn
}

output "max_receive_count" {
  description = "Number of receives before moving a message to the DLQ."
  value       = var.max_receive_count
}

output "visibility_timeout_seconds" {
  description = "Visibility timeout for SQS messages in seconds."
  value       = aws_sqs_queue.main.visibility_timeout_seconds
}

output "message_retention_seconds" {
  description = "Message retention period for the main SQS queue in seconds."
  value       = aws_sqs_queue.main.message_retention_seconds
}
