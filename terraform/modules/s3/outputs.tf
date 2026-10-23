output "raw_bucket_name" {
  description = "Raw data S3 bucket name"
  value       = aws_s3_bucket.raw.bucket
}

output "raw_bucket_arn" {
  description = "Raw data S3 bucket ARN"
  value       = aws_s3_bucket.raw.arn
}

output "raw_bucket_access_policy_arn" {
  description = "IAM policy ARN for Batch and Collector raw bucket access"
  value       = aws_iam_policy.raw_bucket_access.arn
}

output "raw_bucket_prefixes" {
  description = "Raw bucket prefixes"
  value = [
    "raw/",
    "processed/",
    "failed/"
  ]
}
