output "cloudfront_domain_name" {
  description = "CloudFront 배포 도메인명"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront 배포 ID"
  value       = aws_cloudfront_distribution.main.id
}

output "cloudfront_distribution_arn" {
  description = "CloudFront 배포 ARN"
  value       = aws_cloudfront_distribution.main.arn
}

output "cloudfront_hosted_zone_id" {
  description = "CloudFront 배포 Hosted Zone ID (Route53 Alias 설정용)"
  value       = aws_cloudfront_distribution.main.hosted_zone_id
}

output "waf_web_acl_id" {
  description = "WAF Web ACL ID"
  value       = var.enable_waf ? aws_wafv2_web_acl.cloudfront[0].id : null
}

output "waf_web_acl_arn" {
  description = "WAF Web ACL ARN"
  value       = var.enable_waf ? aws_wafv2_web_acl.cloudfront[0].arn : null
}

output "acm_certificate_arn" {
  description = "CloudFront용 ACM 인증서 ARN (us-east-1)"
  value       = local.use_custom_domain ? aws_acm_certificate.cloudfront[0].arn : null
}

output "acm_certificate_status" {
  description = "ACM 인증서 상태"
  value       = local.use_custom_domain ? aws_acm_certificate.cloudfront[0].status : "N/A (no custom domain)"
}

output "route53_zone_id" {
  description = "Route53 Hosted Zone ID"
  value       = local.route53_zone_id
}

output "route53_name_servers" {
  description = "Route53 Name Server 목록 (신규 zone 생성 시)"
  value       = var.create_route53_hosted_zone && local.use_custom_domain ? aws_route53_zone.main[0].name_servers : null
}

output "cloudfront_secret_header_name" {
  description = "ALB 접근 제한용 커스텀 헤더 이름"
  value       = "X-CloudFront-Secret"
}