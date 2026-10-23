terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }

    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  topic_name  = coalesce(var.sns_topic_name, "${local.name_prefix}-monitoring-alert-topic")

  lambda_function_name = coalesce(
    var.lambda_function_name,
    "${local.name_prefix}-cloudwatch-slack-notifier"
  )

  tags = merge(
    var.common_tags,
    {
      Environment = var.environment
      ManagedBy   = "Terraform"
      Component   = "alerting"
      Purpose     = "cloudwatch-alert-slack-notification"
    }
  )

  alarm_actions = var.enable_alarm_actions ? [aws_sns_topic.alerts.arn] : []
  ok_actions    = var.enable_ok_actions ? [aws_sns_topic.alerts.arn] : []
}

resource "aws_secretsmanager_secret" "slack_webhook" {
  name                    = var.slack_webhook_secret_name
  description             = "MoMent ${var.environment} Slack webhook URL for monitoring alerts. Secret value is managed out-of-band."
  recovery_window_in_days = var.slack_webhook_secret_recovery_window_in_days

  tags = merge(local.tags, {
    Name = var.slack_webhook_secret_name
    Role = "slack-webhook-secret"
  })
}

resource "aws_sns_topic" "alerts" {
  name         = local.topic_name
  display_name = var.sns_display_name

  tags = merge(local.tags, {
    Name = local.topic_name
    Role = "cloudwatch-alert-topic"
  })
}

data "archive_file" "slack_notifier_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/slack_notifier.py"
  output_path = "${path.root}/.terraform/${local.lambda_function_name}.zip"
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    sid     = "AllowLambdaAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${local.lambda_function_name}-role"
  description        = "IAM role for MoMent ${var.environment} CloudWatch alarm Slack notifier"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = merge(local.tags, {
    Name = "${local.lambda_function_name}-role"
    Role = "cloudwatch-slack-notifier"
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "lambda_secrets_read" {
  statement {
    sid    = "AllowReadSlackWebhookSecret"
    effect = "Allow"

    actions = [
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue"
    ]

    resources = [
      aws_secretsmanager_secret.slack_webhook.arn
    ]
  }
}

resource "aws_iam_policy" "lambda_secrets_read" {
  name        = "${local.lambda_function_name}-secrets-read-policy"
  description = "Allow Slack notifier Lambda to read only the Slack webhook secret"
  policy      = data.aws_iam_policy_document.lambda_secrets_read.json

  tags = merge(local.tags, {
    Name = "${local.lambda_function_name}-secrets-read-policy"
    Role = "cloudwatch-slack-notifier-secrets-read"
  })
}

resource "aws_iam_role_policy_attachment" "lambda_secrets_read" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.lambda_secrets_read.arn
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.lambda_function_name}"
  retention_in_days = var.lambda_log_retention_days

  tags = merge(local.tags, {
    Name = "/aws/lambda/${local.lambda_function_name}"
    Role = "lambda-log-group"
  })
}

resource "aws_lambda_function" "slack_notifier" {
  function_name = local.lambda_function_name
  description   = "MoMent ${var.environment} CloudWatch alarm Slack notifier"

  role    = aws_iam_role.lambda.arn
  runtime = var.lambda_runtime
  handler = "slack_notifier.lambda_handler"

  filename         = data.archive_file.slack_notifier_zip.output_path
  source_code_hash = data.archive_file.slack_notifier_zip.output_base64sha256

  timeout     = var.lambda_timeout
  memory_size = var.lambda_memory_size

  environment {
    variables = {
      PROJECT_NAME              = var.project_name
      ENVIRONMENT               = var.environment
      SLACK_WEBHOOK_SECRET_NAME = aws_secretsmanager_secret.slack_webhook.name
    }
  }

  tags = merge(local.tags, {
    Name = local.lambda_function_name
    Role = "cloudwatch-slack-notifier"
  })

  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy_attachment.lambda_secrets_read
  ]
}

resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "AllowExecutionFromAlertSns"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.slack_notifier.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.alerts.arn
}

resource "aws_sns_topic_subscription" "lambda" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.slack_notifier.arn

  depends_on = [
    aws_lambda_permission.allow_sns
  ]
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  for_each = var.enable_cloudwatch_alarms ? var.rds_instance_identifiers : {}

  alarm_name = "${local.name_prefix}-rds-${each.key}-cpu-high"
  alarm_description = jsonencode({
    display_name   = "RDSCPUHigh"
    summary        = "${var.environment} RDS CPUUtilization is high for ${each.value}."
    description    = "RDS CPU 사용률이 기준치를 초과했습니다."
    severity       = "high"
    service        = "rds-postgres"
    category       = "aws-data"
    owner          = "Data/Infra"
    reason         = "DB 부하 증가, 쿼리 지연, connection 증가 가능성이 있습니다."
    threshold_text = "CPUUtilization > ${var.rds_cpu_high_threshold}% for 10m"
    action_hint    = "RDS Performance Insights, DatabaseConnections, slow query, backend DB pool, recent deployment를 확인합니다."
    runbook_url    = "docs/runbooks/rds-cpu-high.md"
  })
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = var.rds_cpu_high_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = each.value
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.ok_actions

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-rds-${each.key}-cpu-high"
    Role = "cloudwatch-alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "rds_free_storage_low" {
  for_each = var.enable_cloudwatch_alarms ? var.rds_instance_identifiers : {}

  alarm_name = "${local.name_prefix}-rds-${each.key}-free-storage-low"
  alarm_description = jsonencode({
    display_name   = "RDSFreeStorageLow"
    summary        = "${var.environment} RDS FreeStorageSpace is low for ${each.value}."
    description    = "RDS 남은 저장 공간이 기준치보다 낮습니다."
    severity       = "high"
    service        = "rds-postgres"
    category       = "aws-data"
    owner          = "Data/Infra"
    reason         = "DB 저장공간 부족으로 쓰기 실패 또는 장애가 발생할 수 있습니다."
    threshold_text = "FreeStorageSpace < ${var.rds_free_storage_low_threshold_bytes} bytes for 10m"
    action_hint    = "RDS storage, auto storage scaling, 데이터 증가량, 오래된 데이터 정리 필요 여부를 확인합니다."
    runbook_url    = "docs/runbooks/rds-free-storage-low.md"
  })
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = var.rds_free_storage_low_threshold_bytes
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = each.value
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.ok_actions

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-rds-${each.key}-free-storage-low"
    Role = "cloudwatch-alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "redis_cpu_high" {
  for_each = var.enable_cloudwatch_alarms ? var.redis_replication_group_ids : {}

  alarm_name = "${local.name_prefix}-redis-${each.key}-cpu-high"
  alarm_description = jsonencode({
    display_name   = "RedisCPUHigh"
    summary        = "${var.environment} Redis CPUUtilization is high for ${each.value}."
    description    = "Redis CPU 사용률이 기준치를 초과했습니다."
    severity       = "high"
    service        = "redis"
    category       = "aws-data"
    owner          = "Backend/Infra"
    reason         = "캐시, 분산락, 세션성 요청 부하 증가 가능성이 있습니다."
    threshold_text = "CPUUtilization > ${var.redis_cpu_high_threshold}% for 10m"
    action_hint    = "Redis CPU, commands, connected clients, backend cache/lock 호출량을 확인합니다."
    runbook_url    = "docs/runbooks/redis-cpu-high.md"
  })
  namespace           = "AWS/ElastiCache"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = var.redis_cpu_high_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ReplicationGroupId = each.value
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.ok_actions

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-redis-${each.key}-cpu-high"
    Role = "cloudwatch-alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "redis_evictions" {
  for_each = var.enable_cloudwatch_alarms ? var.redis_replication_group_ids : {}

  alarm_name = "${local.name_prefix}-redis-${each.key}-evictions"
  alarm_description = jsonencode({
    display_name   = "RedisEvictionsDetected"
    summary        = "${var.environment} Redis evictions detected for ${each.value}."
    description    = "Redis eviction이 발생했습니다."
    severity       = "high"
    service        = "redis"
    category       = "aws-data"
    owner          = "Backend/Infra"
    reason         = "메모리 부족으로 캐시 데이터가 제거되고 있을 수 있습니다."
    threshold_text = "Evictions > ${var.redis_evictions_threshold} for 5m"
    action_hint    = "Redis memory usage, eviction policy, hot key, cache TTL, node type 증설 필요 여부를 확인합니다."
    runbook_url    = "docs/runbooks/redis-evictions-detected.md"
  })
  namespace           = "AWS/ElastiCache"
  metric_name         = "Evictions"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = var.redis_evictions_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ReplicationGroupId = each.value
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.ok_actions

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-redis-${each.key}-evictions"
    Role = "cloudwatch-alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "opensearch_cluster_red" {
  for_each = var.enable_cloudwatch_alarms ? var.opensearch_domain_names : {}

  alarm_name = "${local.name_prefix}-opensearch-${each.key}-cluster-red"
  alarm_description = jsonencode({
    display_name   = "OpenSearchRed"
    summary        = "${var.environment} OpenSearch cluster status is red for ${each.value}."
    description    = "OpenSearch cluster가 red 상태입니다."
    severity       = "critical"
    service        = "opensearch"
    category       = "aws-data"
    owner          = "Search/Infra"
    reason         = "Primary shard 미할당 등으로 검색 기능 장애가 발생할 수 있습니다."
    threshold_text = "ClusterStatus.red >= 1 for 5m"
    action_hint    = "OpenSearch cluster health, shard allocation, node status, storage, JVM pressure를 확인합니다."
    runbook_url    = "docs/runbooks/opensearch-red.md"
  })
  namespace           = "AWS/ES"
  metric_name         = "ClusterStatus.red"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DomainName = each.value
    ClientId   = data.aws_caller_identity.current.account_id
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.ok_actions

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-opensearch-${each.key}-cluster-red"
    Role = "cloudwatch-alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "opensearch_cluster_yellow" {
  for_each = var.enable_cloudwatch_alarms ? var.opensearch_domain_names : {}

  alarm_name = "${local.name_prefix}-opensearch-${each.key}-cluster-yellow"
  alarm_description = jsonencode({
    display_name   = "OpenSearchYellow"
    summary        = "${var.environment} OpenSearch cluster status is yellow for ${each.value}."
    description    = "OpenSearch cluster가 yellow 상태입니다."
    severity       = "high"
    service        = "opensearch"
    category       = "aws-data"
    owner          = "Search/Infra"
    reason         = "Replica shard 미할당 또는 노드/스토리지 압박 가능성이 있습니다."
    threshold_text = "ClusterStatus.yellow >= 1 for 10m"
    action_hint    = "OpenSearch node count, shard allocation, storage, JVM pressure, recent index 변경을 확인합니다."
    runbook_url    = "docs/runbooks/opensearch-yellow.md"
  })
  namespace           = "AWS/ES"
  metric_name         = "ClusterStatus.yellow"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DomainName = each.value
    ClientId   = data.aws_caller_identity.current.account_id
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.ok_actions

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-opensearch-${each.key}-cluster-yellow"
    Role = "cloudwatch-alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "sqs_visible_messages_high" {
  for_each = var.enable_cloudwatch_alarms ? var.sqs_queue_names : {}

  alarm_name = "${local.name_prefix}-sqs-${each.key}-visible-messages-high"
  alarm_description = jsonencode({
    display_name   = "SqsBacklogHigh"
    summary        = "${var.environment} SQS visible message count is high for ${each.value}."
    description    = "SQS backlog가 기준치 이상 증가했습니다."
    severity       = "medium"
    service        = "sqs"
    category       = "data-pipeline"
    owner          = "Data/Infra"
    reason         = "Batch worker 처리 지연 또는 consumer 장애 가능성이 있습니다."
    threshold_text = "ApproximateNumberOfMessagesVisible > ${var.sqs_visible_messages_high_threshold} for 10m"
    action_hint    = "batch-job worker, SQS queue depth, DLQ, worker logs, processing latency를 확인합니다."
    runbook_url    = "docs/runbooks/sqs-backlog-high.md"
  })
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = var.sqs_visible_messages_high_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = each.value
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.ok_actions

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-sqs-${each.key}-visible-messages-high"
    Role = "cloudwatch-alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "sqs_dlq_visible_messages" {
  for_each = var.enable_cloudwatch_alarms ? var.sqs_dlq_names : {}

  alarm_name = "${local.name_prefix}-sqs-${each.key}-dlq-visible-messages"
  alarm_description = jsonencode({
    display_name   = "SqsDlqMessagesVisible"
    summary        = "${var.environment} SQS DLQ has visible messages for ${each.value}."
    description    = "SQS DLQ에 실패 메시지가 존재합니다."
    severity       = "critical"
    service        = "sqs-dlq"
    category       = "data-pipeline"
    owner          = "Data/Infra"
    reason         = "처리 실패 데이터가 발생했으며 데이터 유실/누락 검토가 필요합니다."
    threshold_text = "ApproximateNumberOfMessagesVisible > ${var.sqs_dlq_visible_messages_threshold} for 5m"
    action_hint    = "DLQ message body, batch worker error, source payload schema, 재처리 가능 여부를 확인합니다."
    runbook_url    = "docs/runbooks/sqs-dlq-messages-visible.md"
  })
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = var.sqs_dlq_visible_messages_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = each.value
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.ok_actions

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-sqs-${each.key}-dlq-visible-messages"
    Role = "cloudwatch-alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = var.enable_cloudwatch_alarms ? var.lambda_function_names : {}

  alarm_name = "${local.name_prefix}-lambda-${each.key}-errors"
  alarm_description = jsonencode({
    display_name   = "LambdaErrorHigh"
    summary        = "${var.environment} Lambda errors detected for ${each.value}."
    description    = "Lambda error가 발생했습니다."
    severity       = "high"
    service        = "lambda"
    category       = "data-pipeline"
    owner          = "Data/Infra"
    reason         = "공공데이터 수집 또는 Slack 알림 처리 실패 가능성이 있습니다."
    threshold_text = "Errors > ${var.lambda_errors_threshold} for 5m"
    action_hint    = "Lambda CloudWatch Logs, 최근 배포, 외부 API 응답, timeout, permission을 확인합니다."
    runbook_url    = "docs/runbooks/lambda-error-high.md"
  })
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = var.lambda_errors_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = each.value
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.ok_actions

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-lambda-${each.key}-errors"
    Role = "cloudwatch-alarm"
  })
}

# ALB / Target Group resources are created dynamically by AWS Load Balancer Controller.
# Look them up by stable controller tags instead of hardcoding generated names or ARNs.
data "aws_resourcegroupstaggingapi_resources" "application_load_balancers" {
  for_each = var.enable_cloudwatch_alarms ? var.application_load_balancer_tag_selectors : {}

  resource_type_filters = ["elasticloadbalancing:loadbalancer"]

  dynamic "tag_filter" {
    for_each = each.value.tags

    content {
      key    = tag_filter.key
      values = [tag_filter.value]
    }
  }
}

data "aws_resourcegroupstaggingapi_resources" "target_groups" {
  for_each = var.enable_cloudwatch_alarms ? var.target_group_tag_selectors : {}

  resource_type_filters = ["elasticloadbalancing:targetgroup"]

  dynamic "tag_filter" {
    for_each = each.value.tags

    content {
      key    = tag_filter.key
      values = [tag_filter.value]
    }
  }
}

locals {
  application_load_balancer_arns = {
    for key, resources in data.aws_resourcegroupstaggingapi_resources.application_load_balancers :
    key => resources.resource_tag_mapping_list[0].resource_arn
    if length(resources.resource_tag_mapping_list) > 0
  }

  application_load_balancer_arn_suffixes = {
    for key, arn in local.application_load_balancer_arns :
    key => replace(arn, "/^arn:[^:]+:elasticloadbalancing:[^:]+:[0-9]+:loadbalancer\\//", "")
  }

  target_group_arns = {
    for key, resources in data.aws_resourcegroupstaggingapi_resources.target_groups :
    key => resources.resource_tag_mapping_list[0].resource_arn
    if length(resources.resource_tag_mapping_list) > 0
  }

  target_group_arn_suffixes = {
    for key, arn in local.target_group_arns :
    key => replace(arn, "/^arn:[^:]+:elasticloadbalancing:[^:]+:[0-9]+:/", "")
  }

  target_group_alarm_dimensions = {
    for key, target_group in local.target_group_arn_suffixes :
    key => {
      target_group  = target_group
      load_balancer = local.application_load_balancer_arn_suffixes[var.target_group_tag_selectors[key].load_balancer_key]
    }
    if contains(keys(local.application_load_balancer_arn_suffixes), var.target_group_tag_selectors[key].load_balancer_key)
  }
}

resource "aws_cloudwatch_metric_alarm" "alb_elb_5xx_count" {
  for_each = var.enable_cloudwatch_alarms ? local.application_load_balancer_arn_suffixes : {}

  alarm_name = "${local.name_prefix}-alb-${each.key}-elb-5xx-count"
  alarm_description = jsonencode({
    display_name   = "ALB5xxHigh"
    summary        = "${var.environment} ALB generated HTTP 5XX responses for ${each.key}."
    description    = "ALB 5xx 응답이 발생했습니다."
    severity       = "high"
    service        = "alb"
    category       = "aws-edge"
    owner          = "Infra/Backend"
    reason         = "ALB 자체 오류 또는 target 연결 문제가 발생했을 수 있습니다."
    threshold_text = "HTTPCode_ELB_5XX_Count >= ${var.alb_elb_5xx_count_threshold} within 5m"
    action_hint    = "ALB listener/rule, target group health, backend pod, ingress event, recent deployment를 확인합니다."
    runbook_url    = "docs/runbooks/alb-5xx-high.md"
  })
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_ELB_5XX_Count"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 1
  threshold           = var.alb_elb_5xx_count_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = each.value
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.ok_actions

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-alb-${each.key}-elb-5xx-count"
    Role = "cloudwatch-alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "alb_target_response_time_high" {
  for_each = var.enable_cloudwatch_alarms ? local.application_load_balancer_arn_suffixes : {}

  alarm_name = "${local.name_prefix}-alb-${each.key}-target-response-time-high"
  alarm_description = jsonencode({
    display_name   = "ALBLatencyHigh"
    summary        = "${var.environment} ALB TargetResponseTime is high for ${each.key}."
    description    = "ALB TargetResponseTime이 기준치를 초과했습니다."
    severity       = "high"
    service        = "alb"
    category       = "aws-edge"
    owner          = "Infra/Backend"
    reason         = "Backend API 지연, DB/Redis/OpenSearch 지연, Pod 리소스 압박 가능성이 있습니다."
    threshold_text = "TargetResponseTime > ${var.alb_target_response_time_high_threshold_seconds}s for 5m"
    action_hint    = "Backend latency, pod CPU/memory, DB query, Redis/OpenSearch latency, ALB target health를 확인합니다."
    runbook_url    = "docs/runbooks/alb-latency-high.md"
  })
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 3
  threshold           = var.alb_target_response_time_high_threshold_seconds
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = each.value
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.ok_actions

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-alb-${each.key}-target-response-time-high"
    Role = "cloudwatch-alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "target_group_unhealthy_hosts" {
  for_each = var.enable_cloudwatch_alarms ? local.target_group_alarm_dimensions : {}

  alarm_name = "${local.name_prefix}-tg-${each.key}-unhealthy-hosts"
  alarm_description = jsonencode({
    display_name   = "TargetGroupUnhealthyHosts"
    summary        = "${var.environment} Target Group has unhealthy targets for ${each.key}."
    description    = "TargetGroup에 unhealthy target이 존재합니다."
    severity       = "high"
    service        = "alb-target-group"
    category       = "aws-edge"
    owner          = "Infra/Backend"
    reason         = "Pod readiness 실패, Service/Endpoint 문제, health check path 불일치 가능성이 있습니다."
    threshold_text = "UnHealthyHostCount > ${var.target_group_unhealthy_host_count_threshold} within 5m"
    action_hint    = "TargetGroup health reason, backend pod readiness, Service endpoint, Ingress annotation을 확인합니다."
    runbook_url    = "docs/runbooks/target-group-unhealthy-hosts.md"
  })
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 1
  threshold           = var.target_group_unhealthy_host_count_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = each.value.load_balancer
    TargetGroup  = each.value.target_group
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.ok_actions

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-tg-${each.key}-unhealthy-hosts"
    Role = "cloudwatch-alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "target_group_5xx_count" {
  for_each = var.enable_cloudwatch_alarms ? local.target_group_alarm_dimensions : {}

  alarm_name = "${local.name_prefix}-tg-${each.key}-target-5xx-count"
  alarm_description = jsonencode({
    display_name   = "TargetGroup5xxHigh"
    summary        = "${var.environment} Target Group generated HTTP 5XX responses for ${each.key}."
    description    = "TargetGroup backend target에서 5xx 응답이 발생했습니다."
    severity       = "high"
    service        = "backend-api"
    category       = "aws-edge"
    owner          = "Infra/Backend"
    reason         = "Backend API 오류 또는 downstream dependency 장애 가능성이 있습니다."
    threshold_text = "HTTPCode_Target_5XX_Count >= ${var.target_group_5xx_count_threshold} within 5m"
    action_hint    = "Backend logs, failing endpoint, DB/Redis/OpenSearch connectivity, recent deployment를 확인합니다."
    runbook_url    = "docs/runbooks/target-group-5xx-high.md"
  })
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 1
  threshold           = var.target_group_5xx_count_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = each.value.load_balancer
    TargetGroup  = each.value.target_group
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.ok_actions

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-tg-${each.key}-target-5xx-count"
    Role = "cloudwatch-alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "rds_connection_high" {
  for_each = var.enable_cloudwatch_alarms ? var.rds_instance_identifiers : {}

  alarm_name = "${local.name_prefix}-rds-${each.key}-connection-high"
  alarm_description = jsonencode({
    display_name   = "RDSConnectionHigh"
    severity       = "high"
    service        = "rds-postgres"
    category       = "database"
    owner          = "Backend/Data"
    reason         = "RDS database connections are close to the configured threshold. Application connection pool pressure or leaked connections may be occurring."
    threshold_text = "DatabaseConnections > ${var.rds_connection_high_threshold} for 10m"
    action_hint    = "Check backend connection pool, active sessions, slow queries, and RDS Performance Insights."
    runbook_url    = "docs/runbooks/rds-connection-high.md"
  })

  namespace           = "AWS/RDS"
  metric_name         = "DatabaseConnections"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = var.rds_connection_high_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = each.value
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.ok_actions

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-rds-${each.key}-connection-high"
    Role = "cloudwatch-alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "redis_memory_high" {
  for_each = var.enable_cloudwatch_alarms ? var.redis_replication_group_ids : {}

  alarm_name = "${local.name_prefix}-redis-${each.key}-memory-high"
  alarm_description = jsonencode({
    display_name   = "RedisMemoryHigh"
    severity       = "high"
    service        = "redis"
    category       = "cache"
    owner          = "Backend/Infra"
    reason         = "Redis memory usage is high and can lead to evictions or degraded cache and lock behavior."
    threshold_text = "DatabaseMemoryUsagePercentage > ${var.redis_memory_high_threshold_percent}% for 10m"
    action_hint    = "Check Redis memory usage, evictions, key cardinality, TTL policy, and application cache behavior."
    runbook_url    = "docs/runbooks/redis-memory-high.md"
  })

  namespace           = "AWS/ElastiCache"
  metric_name         = "DatabaseMemoryUsagePercentage"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = var.redis_memory_high_threshold_percent
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ReplicationGroupId = each.value
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.ok_actions

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-redis-${each.key}-memory-high"
    Role = "cloudwatch-alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  for_each = var.enable_cloudwatch_alarms ? var.lambda_function_names : {}

  alarm_name = "${local.name_prefix}-lambda-${each.key}-throttles"
  alarm_description = jsonencode({
    display_name   = "LambdaThrottleDetected"
    severity       = "medium"
    service        = "lambda"
    category       = "data-pipeline"
    owner          = "Data/Infra"
    reason         = "Lambda throttling was detected. Data collection can be delayed or retried."
    threshold_text = "Throttles > ${var.lambda_throttles_threshold} for 5m"
    action_hint    = "Check Lambda concurrency, retry behavior, scheduler frequency, and recent collector executions."
    runbook_url    = "docs/runbooks/lambda-throttles-detected.md"
  })

  namespace           = "AWS/Lambda"
  metric_name         = "Throttles"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = var.lambda_throttles_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = each.value
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.ok_actions

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-lambda-${each.key}-throttles"
    Role = "cloudwatch-alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "sqs_oldest_message_high" {
  for_each = var.enable_cloudwatch_alarms ? var.sqs_queue_names : {}

  alarm_name = "${local.name_prefix}-sqs-${each.key}-oldest-message-high"
  alarm_description = jsonencode({
    display_name   = "SqsOldMessageHigh"
    severity       = "high"
    service        = "sqs"
    category       = "data-pipeline"
    owner          = "Data/Infra"
    reason         = "Old SQS messages indicate worker processing delay or consumer failure."
    threshold_text = "ApproximateAgeOfOldestMessage > ${var.sqs_oldest_message_high_threshold_seconds}s for 10m"
    action_hint    = "Check batch worker availability, SQS consumer logs, DLQ movement, and downstream RDS/OpenSearch latency."
    runbook_url    = "docs/runbooks/sqs-old-message-high.md"
  })

  namespace           = "AWS/SQS"
  metric_name         = "ApproximateAgeOfOldestMessage"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = var.sqs_oldest_message_high_threshold_seconds
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = each.value
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.ok_actions

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-sqs-${each.key}-oldest-message-high"
    Role = "cloudwatch-alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "opensearch_cpu_high" {
  for_each = var.enable_cloudwatch_alarms ? var.opensearch_domain_names : {}

  alarm_name = "${local.name_prefix}-opensearch-${each.key}-cpu-high"
  alarm_description = jsonencode({
    display_name   = "OpenSearchCPUHigh"
    severity       = "high"
    service        = "opensearch"
    category       = "search"
    owner          = "Search/Infra"
    reason         = "OpenSearch CPU utilization is high and can affect search latency or indexing throughput."
    threshold_text = "CPUUtilization > ${var.opensearch_cpu_high_threshold}% for 10m"
    action_hint    = "Check OpenSearch CPU, JVM pressure, slow queries, indexing load, shard health, and backend search traffic."
    runbook_url    = "docs/runbooks/opensearch-cpu-high.md"
  })

  namespace           = "AWS/ES"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = var.opensearch_cpu_high_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DomainName = each.value
    ClientId   = data.aws_caller_identity.current.account_id
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.ok_actions

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-opensearch-${each.key}-cpu-high"
    Role = "cloudwatch-alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "opensearch_jvm_memory_pressure_high" {
  for_each = var.enable_cloudwatch_alarms ? var.opensearch_domain_names : {}

  alarm_name = "${local.name_prefix}-opensearch-${each.key}-jvm-memory-pressure-high"
  alarm_description = jsonencode({
    display_name   = "OpenSearchJVMMemoryPressureHigh"
    severity       = "high"
    service        = "opensearch"
    category       = "search"
    owner          = "Search/Infra"
    reason         = "OpenSearch JVM memory pressure is high and can cause search latency, GC pressure, or cluster instability."
    threshold_text = "JVMMemoryPressure > ${var.opensearch_jvm_memory_pressure_high_threshold}% for 10m"
    action_hint    = "Check JVM memory pressure, shard count, heap pressure, query volume, indexing load, and OpenSearch cluster health."
    runbook_url    = "docs/runbooks/opensearch-jvm-memory-pressure-high.md"
  })

  namespace           = "AWS/ES"
  metric_name         = "JVMMemoryPressure"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = var.opensearch_jvm_memory_pressure_high_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DomainName = each.value
    ClientId   = data.aws_caller_identity.current.account_id
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.ok_actions

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-opensearch-${each.key}-jvm-memory-pressure-high"
    Role = "cloudwatch-alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "opensearch_free_storage_low" {
  for_each = var.enable_cloudwatch_alarms ? var.opensearch_domain_names : {}

  alarm_name = "${local.name_prefix}-opensearch-${each.key}-free-storage-low"
  alarm_description = jsonencode({
    display_name   = "OpenSearchFreeStorageLow"
    severity       = "high"
    service        = "opensearch"
    category       = "search"
    owner          = "Search/Infra"
    reason         = "OpenSearch free storage is low and can affect indexing, search stability, or cluster health."
    threshold_text = "FreeStorageSpace < ${var.opensearch_free_storage_low_threshold_mb} MiB for 10m"
    action_hint    = "Check OpenSearch free storage, index size, shard allocation, old indices, and data retention policy."
    runbook_url    = "docs/runbooks/opensearch-free-storage-low.md"
  })

  namespace           = "AWS/ES"
  metric_name         = "FreeStorageSpace"
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = var.opensearch_free_storage_low_threshold_mb
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DomainName = each.value
    ClientId   = data.aws_caller_identity.current.account_id
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.ok_actions

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-opensearch-${each.key}-free-storage-low"
    Role = "cloudwatch-alarm"
  })
}

resource "aws_cloudwatch_metric_alarm" "target_group_healthy_host_zero" {
  for_each = var.enable_cloudwatch_alarms ? local.target_group_alarm_dimensions : {}

  alarm_name = "${local.name_prefix}-tg-${each.key}-healthy-host-zero"
  alarm_description = jsonencode({
    display_name   = "ALBHealthyHostZero"
    severity       = "critical"
    service        = "alb-target-group"
    category       = "edge"
    owner          = "Infra"
    reason         = "Target Group has zero healthy hosts. External API traffic can fail."
    threshold_text = "HealthyHostCount < ${var.target_group_healthy_host_zero_threshold} within 2m"
    action_hint    = "Check Ingress, TargetGroupBinding, Service endpoints, Pod readiness, ALB controller events, and backend health endpoint."
    runbook_url    = "docs/runbooks/alb-healthy-host-zero.md"
  })

  namespace           = "AWS/ApplicationELB"
  metric_name         = "HealthyHostCount"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = var.target_group_healthy_host_zero_threshold
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = each.value.load_balancer
    TargetGroup  = each.value.target_group
  }

  alarm_actions = local.alarm_actions
  ok_actions    = local.ok_actions

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-tg-${each.key}-healthy-host-zero"
    Role = "cloudwatch-alarm"
  })
}
