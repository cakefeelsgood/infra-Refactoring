data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  bucket_name = coalesce(
    var.bucket_name,
    "${var.project_name}-${var.environment}-profile-image-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"
  )

  object_key_prefix            = trimsuffix(trimprefix(var.object_key_prefix, "/"), "/")
  object_key_prefix_with_slash = "${local.object_key_prefix}/"

  public_url_base = "https://${aws_s3_bucket.this.bucket_regional_domain_name}"

  tags = merge(
    var.common_tags,
    {
      Environment = var.environment
      ManagedBy   = "Terraform"
      Component   = "s3"
      Purpose     = "profile-image-upload"
    }
  )
}

resource "aws_s3_bucket" "this" {
  bucket        = local.bucket_name
  force_destroy = var.force_destroy

  tags = merge(local.tags, {
    Name = local.bucket_name
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = !var.public_read_enabled
  ignore_public_acls      = true
  restrict_public_buckets = !var.public_read_enabled
}

data "aws_iam_policy_document" "public_read" {
  count = var.public_read_enabled ? 1 : 0

  statement {
    sid    = "AllowPublicReadForProfileImages"
    effect = "Allow"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = [
      "s3:GetObject"
    ]

    resources = [
      "${aws_s3_bucket.this.arn}/${local.object_key_prefix_with_slash}*"
    ]
  }
}

resource "aws_s3_bucket_policy" "public_read" {
  count = var.public_read_enabled ? 1 : 0

  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.public_read[0].json

  depends_on = [
    aws_s3_bucket_public_access_block.this
  ]
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "profile-image-object-lifecycle"
    status = "Enabled"

    filter {
      prefix = local.object_key_prefix_with_slash
    }

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = var.abort_incomplete_multipart_upload_days
    }
  }

  depends_on = [
    aws_s3_bucket_versioning.this
  ]
}

resource "aws_s3_bucket_cors_configuration" "this" {
  count = length(var.cors_allowed_origins) > 0 ? 1 : 0

  bucket = aws_s3_bucket.this.id

  cors_rule {
    allowed_headers = var.cors_allowed_headers
    allowed_methods = var.cors_allowed_methods
    allowed_origins = var.cors_allowed_origins
    expose_headers  = var.cors_expose_headers
    max_age_seconds = var.cors_max_age_seconds
  }
}
