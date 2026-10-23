output "lambda_function_name" {
  description = "Lambda Collector function name."
  value       = aws_lambda_function.collector.function_name
}

output "lambda_function_arn" {
  description = "Lambda Collector function ARN."
  value       = aws_lambda_function.collector.arn
}

output "lambda_log_group_name" {
  description = "Lambda Collector CloudWatch log group name."
  value       = aws_cloudwatch_log_group.collector.name
}

output "scheduler_schedule_group_name" {
  description = "EventBridge Scheduler schedule group name."
  value       = aws_scheduler_schedule_group.collector.name
}

output "scheduler_schedule_name" {
  description = "EventBridge Scheduler schedule name."
  value       = aws_scheduler_schedule.collector.name
}

output "scheduler_schedule_arn" {
  description = "EventBridge Scheduler schedule ARN."
  value       = aws_scheduler_schedule.collector.arn
}

output "scheduler_invoke_lambda_role_arn" {
  description = "IAM role ARN used by EventBridge Scheduler to invoke Lambda Collector."
  value       = aws_iam_role.scheduler_invoke_lambda.arn
}
