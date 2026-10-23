output "bucket_name" {
  description = "Profile image S3 bucket name."
  value       = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  description = "Profile image S3 bucket ARN."
  value       = aws_s3_bucket.this.arn
}

output "bucket_id" {
  description = "Profile image S3 bucket ID."
  value       = aws_s3_bucket.this.id
}

output "bucket_regional_domain_name" {
  description = "Profile image S3 bucket regional domain name."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "public_url_base" {
  description = "Default public URL base for profile image objects. Replace with CloudFront URL when CDN is connected."
  value       = local.public_url_base
}

output "object_key_prefix" {
  description = "Profile image object key prefix."
  value       = local.object_key_prefix
}
