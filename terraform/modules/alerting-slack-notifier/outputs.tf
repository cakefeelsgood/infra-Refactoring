output "sns_topic_name" {
  description = "CloudWatch alert SNS topic name."
  value       = aws_sns_topic.alerts.name
}

output "sns_topic_arn" {
  description = "CloudWatch alert SNS topic ARN."
  value       = aws_sns_topic.alerts.arn
}

output "lambda_function_name" {
  description = "Slack notifier Lambda function name."
  value       = aws_lambda_function.slack_notifier.function_name
}

output "lambda_function_arn" {
  description = "Slack notifier Lambda function ARN."
  value       = aws_lambda_function.slack_notifier.arn
}

output "lambda_log_group_name" {
  description = "Slack notifier Lambda CloudWatch log group name."
  value       = aws_cloudwatch_log_group.lambda.name
}

output "slack_webhook_secret_name" {
  description = "Slack webhook Secrets Manager secret name."
  value       = aws_secretsmanager_secret.slack_webhook.name
}

output "slack_webhook_secret_arn" {
  description = "Slack webhook Secrets Manager secret ARN."
  value       = aws_secretsmanager_secret.slack_webhook.arn
}

output "cloudwatch_alarm_names" {
  description = "CloudWatch alarm names created by this module."
  value = concat(
    [for alarm in aws_cloudwatch_metric_alarm.rds_cpu_high : alarm.alarm_name],
    [for alarm in aws_cloudwatch_metric_alarm.rds_free_storage_low : alarm.alarm_name],
    [for alarm in aws_cloudwatch_metric_alarm.redis_cpu_high : alarm.alarm_name],
    [for alarm in aws_cloudwatch_metric_alarm.redis_evictions : alarm.alarm_name],
    [for alarm in aws_cloudwatch_metric_alarm.opensearch_cluster_red : alarm.alarm_name],
    [for alarm in aws_cloudwatch_metric_alarm.opensearch_cluster_yellow : alarm.alarm_name],
    [for alarm in aws_cloudwatch_metric_alarm.sqs_visible_messages_high : alarm.alarm_name],
    [for alarm in aws_cloudwatch_metric_alarm.sqs_dlq_visible_messages : alarm.alarm_name],
    [for alarm in aws_cloudwatch_metric_alarm.lambda_errors : alarm.alarm_name],
    [for alarm in aws_cloudwatch_metric_alarm.alb_elb_5xx_count : alarm.alarm_name],
    [for alarm in aws_cloudwatch_metric_alarm.alb_target_response_time_high : alarm.alarm_name],
    [for alarm in aws_cloudwatch_metric_alarm.target_group_unhealthy_hosts : alarm.alarm_name],
    [for alarm in aws_cloudwatch_metric_alarm.target_group_5xx_count : alarm.alarm_name],
    [for alarm in aws_cloudwatch_metric_alarm.rds_connection_high : alarm.alarm_name],
    [for alarm in aws_cloudwatch_metric_alarm.redis_memory_high : alarm.alarm_name],
    [for alarm in aws_cloudwatch_metric_alarm.lambda_throttles : alarm.alarm_name],
    [for alarm in aws_cloudwatch_metric_alarm.sqs_oldest_message_high : alarm.alarm_name],
    [for alarm in aws_cloudwatch_metric_alarm.opensearch_cpu_high : alarm.alarm_name],
    [for alarm in aws_cloudwatch_metric_alarm.opensearch_jvm_memory_pressure_high : alarm.alarm_name],
    [for alarm in aws_cloudwatch_metric_alarm.opensearch_free_storage_low : alarm.alarm_name],
    [for alarm in aws_cloudwatch_metric_alarm.target_group_healthy_host_zero : alarm.alarm_name]
  )
}
