output "topic_name" {
  description = "Notification SNS topic name."
  value       = aws_sns_topic.this.name
}

output "topic_arn" {
  description = "Notification SNS topic ARN."
  value       = aws_sns_topic.this.arn
}

output "topic_id" {
  description = "Notification SNS topic ID."
  value       = aws_sns_topic.this.id
}
