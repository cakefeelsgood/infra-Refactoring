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

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  tags = merge(
    var.common_tags,
    {
      Environment = var.environment
      ManagedBy   = "Terraform"
      Component   = "data-pipeline"
    }
  )
}

data "archive_file" "collector_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/collector.py"
  output_path = "${path.module}/${var.lambda_function_name}.zip"
}

resource "aws_cloudwatch_log_group" "collector" {
  name              = "/aws/lambda/${var.lambda_function_name}"
  retention_in_days = var.log_retention_days

  tags = merge(local.tags, {
    Name = "/aws/lambda/${var.lambda_function_name}"
    Role = "lambda-log-group"
  })
}

resource "aws_lambda_function" "collector" {
  function_name = var.lambda_function_name
  description   = "MoMent ${var.environment} public data Lambda Collector"

  role    = var.lambda_role_arn
  runtime = var.lambda_runtime
  handler = "collector.lambda_handler"

  filename         = data.archive_file.collector_zip.output_path
  source_code_hash = data.archive_file.collector_zip.output_base64sha256

  timeout     = var.lambda_timeout
  memory_size = var.lambda_memory_size

  environment {
    variables = {
      PROJECT_NAME                      = var.project_name
      ENVIRONMENT                       = var.environment
      RAW_BUCKET_NAME                   = var.raw_bucket_name
      QUEUE_URL                         = var.queue_url
      PUBLIC_DATA_API_URL               = var.public_data_api_url
      DATA_PIPELINE_SOURCES_JSON        = ""
      DATA_PIPELINE_SOURCES_SECRET_NAME = var.public_data_sources_secret_name
      raw_bucket_name                   = var.raw_bucket_name
      queue_url                         = var.queue_url
    }
  }

  tags = merge(local.tags, {
    Name = var.lambda_function_name
    Role = "lambda-collector"
  })

  depends_on = [
    aws_cloudwatch_log_group.collector
  ]
}

resource "aws_scheduler_schedule_group" "collector" {
  name = "${local.name_prefix}-public-data-schedule-group"

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-public-data-schedule-group"
    Role = "scheduler-group"
  })
}

data "aws_iam_policy_document" "scheduler_assume_role" {
  statement {
    sid     = "AllowSchedulerAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "scheduler_invoke_lambda" {
  name               = "${local.name_prefix}-scheduler-invoke-lambda-role"
  description        = "IAM role for EventBridge Scheduler to invoke Lambda Collector"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume_role.json

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-scheduler-invoke-lambda-role"
    Role = "scheduler-invoke-lambda"
  })
}

data "aws_iam_policy_document" "scheduler_invoke_lambda" {
  statement {
    sid    = "AllowInvokeLambdaCollector"
    effect = "Allow"

    actions = [
      "lambda:InvokeFunction"
    ]

    resources = [
      aws_lambda_function.collector.arn
    ]
  }
}

resource "aws_iam_policy" "scheduler_invoke_lambda" {
  name        = "${local.name_prefix}-scheduler-invoke-lambda-policy"
  description = "Allow EventBridge Scheduler to invoke Lambda Collector"
  policy      = data.aws_iam_policy_document.scheduler_invoke_lambda.json

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "scheduler_invoke_lambda" {
  role       = aws_iam_role.scheduler_invoke_lambda.name
  policy_arn = aws_iam_policy.scheduler_invoke_lambda.arn
}

resource "aws_scheduler_schedule" "collector" {
  name        = "${local.name_prefix}-public-data-collector-schedule"
  group_name  = aws_scheduler_schedule_group.collector.name
  description = "Schedule for MoMent ${var.environment} public data collector"

  schedule_expression = var.schedule_expression
  state               = var.schedule_state

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.collector.arn
    role_arn = aws_iam_role.scheduler_invoke_lambda.arn

    input = jsonencode({
      source      = "eventbridge-scheduler"
      project     = var.project_name
      environment = var.environment
    })
  }
}

resource "aws_lambda_permission" "allow_scheduler" {
  statement_id  = "AllowExecutionFromEventBridgeScheduler"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.collector.function_name
  principal     = "scheduler.amazonaws.com"
  source_arn    = aws_scheduler_schedule.collector.arn
}
