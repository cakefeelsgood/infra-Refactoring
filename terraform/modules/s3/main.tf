data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  raw_bucket_name = coalesce(
    var.bucket_name,
    "${var.project_name}-${var.environment}-raw-data-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"
  )

  tags = merge(
    var.common_tags,
    {
      Environment = var.environment
      ManagedBy   = "Terraform"
      Purpose     = "public-data-raw-storage"
    }
  )
}

resource "aws_s3_bucket" "raw" {
  bucket        = local.raw_bucket_name
  force_destroy = var.force_destroy

  tags = merge(local.tags, {
    Name = local.raw_bucket_name
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "raw" {
  bucket = aws_s3_bucket.raw.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "raw" {
  bucket = aws_s3_bucket.raw.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "raw" {
  bucket = aws_s3_bucket.raw.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "raw" {
  bucket = aws_s3_bucket.raw.id

  rule {
    id     = "raw-data-expiration"
    status = "Enabled"

    filter {
      prefix = "raw/"
    }

    expiration {
      days = var.raw_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  rule {
    id     = "processed-data-expiration"
    status = "Enabled"

    filter {
      prefix = "processed/"
    }

    expiration {
      days = var.processed_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  rule {
    id     = "failed-data-expiration"
    status = "Enabled"

    filter {
      prefix = "failed/"
    }

    expiration {
      days = var.failed_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_s3_object" "prefixes" {
  for_each = toset([
    "raw/",
    "processed/",
    "failed/"
  ])

  bucket  = aws_s3_bucket.raw.id
  key     = each.key
  content = ""

  server_side_encryption = "AES256"
}

data "aws_iam_policy_document" "raw_bucket_access" {
  statement {
    sid    = "AllowRawBucketList"
    effect = "Allow"

    actions = [
      "s3:ListBucket"
    ]

    resources = [
      aws_s3_bucket.raw.arn
    ]
  }

  statement {
    sid    = "AllowRawBucketObjectAccess"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject"
    ]

    resources = [
      "${aws_s3_bucket.raw.arn}/raw/*",
      "${aws_s3_bucket.raw.arn}/processed/*",
      "${aws_s3_bucket.raw.arn}/failed/*"
    ]
  }
}

resource "aws_iam_policy" "raw_bucket_access" {
  name        = "${var.project_name}-${var.environment}-raw-bucket-access-policy"
  description = "IAM policy for Batch and Collector to access public data raw bucket"
  policy      = data.aws_iam_policy_document.raw_bucket_access.json

  tags = local.tags
}
