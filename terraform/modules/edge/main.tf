terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 5.0"
      configuration_aliases = [aws.us_east_1]
    }
  }
}

locals {
  use_custom_domain        = var.domain_name != null && var.domain_name != ""
  route53_hosted_zone_name = var.hosted_zone_name != null && var.hosted_zone_name != "" ? var.hosted_zone_name : var.domain_name
  alb_has_origin           = var.alb_dns_name != null && var.alb_dns_name != ""
  origin_domain            = local.alb_has_origin ? var.alb_dns_name : "placeholder.ap-northeast-3.elb.amazonaws.com"
  origin_protocol          = var.alb_https_enabled ? "https-only" : "http-only"
}

##############################################
# Route53 Hosted Zone (optional)
##############################################
resource "aws_route53_zone" "main" {
  count   = var.create_route53_hosted_zone && local.use_custom_domain ? 1 : 0
  name    = local.route53_hosted_zone_name
  comment = "${var.name_prefix} managed hosted zone"

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-hosted-zone"
  })
}

data "aws_route53_zone" "existing" {
  count        = !var.create_route53_hosted_zone && local.use_custom_domain ? 1 : 0
  name         = local.route53_hosted_zone_name
  private_zone = false
}

locals {
  route53_zone_id = (
    var.create_route53_hosted_zone && local.use_custom_domain
    ? aws_route53_zone.main[0].zone_id
    : (!var.create_route53_hosted_zone && local.use_custom_domain
      ? data.aws_route53_zone.existing[0].zone_id
      : null
    )
  )
}

##############################################
# ACM Certificate (us-east-1 — CloudFront 전용)
##############################################
resource "aws_acm_certificate" "cloudfront" {
  count             = local.use_custom_domain ? 1 : 0
  provider          = aws.us_east_1
  domain_name       = var.domain_name
  validation_method = "DNS"

  subject_alternative_names = var.subject_alternative_names

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-cloudfront-acm"
  })
}

# Route53 DNS 검증 레코드 (zone 있을 때만 자동 생성)
resource "aws_route53_record" "acm_validation" {
  for_each = (
    local.use_custom_domain && local.route53_zone_id != null
    ? {
      for dvo in aws_acm_certificate.cloudfront[0].domain_validation_options :
      dvo.domain_name => {
        name   = dvo.resource_record_name
        record = dvo.resource_record_value
        type   = dvo.resource_record_type
      }
    }
    : {}
  )

  zone_id         = local.route53_zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "cloudfront" {
  count                   = local.use_custom_domain && local.route53_zone_id != null ? 1 : 0
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.cloudfront[0].arn
  validation_record_fqdns = [for r in aws_route53_record.acm_validation : r.fqdn]
}

##############################################
# WAF Web ACL (us-east-1, scope = CLOUDFRONT)
##############################################
resource "aws_wafv2_web_acl" "cloudfront" {
  count       = var.enable_waf ? 1 : 0
  provider    = aws.us_east_1
  name        = "${var.name_prefix}-cloudfront-waf-acl"
  description = "WAF Web ACL for ${var.name_prefix} CloudFront"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  # Rule 1: 공통 웹 공격 방어 (SQLi, XSS 등)
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 10

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name_prefix}-common-rule-set"
      sampled_requests_enabled   = true
    }
  }

  # Rule 2: 알려진 악성 입력 차단
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 20

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name_prefix}-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # Rule 3: AWS IP 평판 리스트 (봇, DDoS 소스 차단)
  rule {
    name     = "AWSManagedRulesAmazonIpReputationList"
    priority = 30

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name_prefix}-ip-reputation"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name_prefix}-cloudfront-waf"
    sampled_requests_enabled   = true
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-cloudfront-waf-acl"
  })
}

##############################################
# CloudFront Distribution
##############################################
resource "aws_cloudfront_distribution" "main" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "${var.name_prefix} CloudFront Distribution"
  price_class     = var.price_class
  web_acl_id      = var.enable_waf ? aws_wafv2_web_acl.cloudfront[0].arn : null
  aliases         = local.use_custom_domain ? concat([var.domain_name], var.subject_alternative_names) : []

  # Origin: Prod ALB
  # ALB 미구성 시 placeholder 사용 — ALB 생성 후 alb_dns_name 변수 업데이트 필요
  origin {
    domain_name = local.origin_domain
    origin_id   = "prod-alb"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = local.origin_protocol
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    # CloudFront → ALB 접근 제한 전략: Custom Secret Header
    # ALB 쪽 WAF/Listener Rule에서 이 헤더 검증하여 직접 접근 차단
    custom_header {
      name  = "X-CloudFront-Secret"
      value = var.cloudfront_secret_header_value
    }
  }

  # 기본 캐시 동작 — API 백엔드이므로 캐싱 비활성화 (TTL=0)
  default_cache_behavior {
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "prod-alb"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0

    forwarded_values {
      query_string = true
      headers      = ["Host", "Authorization", "Accept", "Accept-Language", "Origin", "Referer"]

      cookies {
        forward = "all"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # 도메인 유무에 따라 인증서 분기
  viewer_certificate {
    cloudfront_default_certificate = local.use_custom_domain ? false : true
    acm_certificate_arn = (
      local.use_custom_domain
      ? (
        local.route53_zone_id != null
        ? aws_acm_certificate_validation.cloudfront[0].certificate_arn
        : aws_acm_certificate.cloudfront[0].arn
      )
      : null
    )
    ssl_support_method       = local.use_custom_domain ? "sni-only" : null
    minimum_protocol_version = local.use_custom_domain ? "TLSv1.2_2021" : null
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-cloudfront"
  })

  lifecycle {
    precondition {
      condition     = var.alb_dns_name != null && var.alb_dns_name != ""
      error_message = "alb_dns_name이 비어 있습니다. Prod ALB 구성 완료 후 prod_alb_dns_name 변수를 설정하세요. ALB Controller/Ingress 준비 전에는 Edge 실제 연결 검증이 제한됩니다."
    }
  }
}



##############################################
# Route53 Alias → CloudFront (도메인 있을 때만)
##############################################
resource "aws_route53_record" "cloudfront_alias" {
  count   = local.use_custom_domain && local.route53_zone_id != null ? 1 : 0
  zone_id = local.route53_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}