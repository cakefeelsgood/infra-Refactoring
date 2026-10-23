variable "name_prefix" {
  description = "리소스 이름 접두사 (예: moment-prod)"
  type        = string
}

variable "tags" {
  description = "공통 태그"
  type        = map(string)
  default     = {}
}

# ─── 도메인 / Route53 ──────────────────────────────────────────────
variable "domain_name" {
  description = "커스텀 도메인명 (없으면 빈 문자열 → CloudFront 기본 도메인 사용)"
  type        = string
  default     = ""
}

variable "hosted_zone_name" {
  description = "Route53 Hosted Zone 이름. 예: moment-team04.click. 비워두면 domain_name을 사용"
  type        = string
  default     = ""
}

variable "subject_alternative_names" {
  description = "ACM 인증서 추가 도메인 (예: [\"www.example.com\"])"
  type        = list(string)
  default     = []
}

variable "create_route53_hosted_zone" {
  description = "Route53 Hosted Zone 신규 생성 여부 (false = 기존 zone 조회)"
  type        = bool
  default     = false
}

# ─── ALB Origin ────────────────────────────────────────────────────
variable "alb_dns_name" {
  description = "Prod ALB DNS 이름 (CloudFront Origin). 미설정 시 placeholder 사용"
  type        = string
  default     = ""
}

variable "alb_https_enabled" {
  description = "CloudFront → ALB 구간 HTTPS 사용 여부 (ALB에 ACM 인증서 필요)"
  type        = bool
  default     = false
}

# ─── CloudFront ────────────────────────────────────────────────────
variable "price_class" {
  description = "CloudFront 요금제 클래스"
  type        = string
  default     = "PriceClass_All"
  validation {
    condition     = contains(["PriceClass_All", "PriceClass_200", "PriceClass_100"], var.price_class)
    error_message = "price_class는 PriceClass_All, PriceClass_200, PriceClass_100 중 하나여야 합니다."
  }
}

variable "cloudfront_secret_header_value" {
  description = "CloudFront → ALB 직접 접근 차단용 커스텀 헤더 값 (X-CloudFront-Secret)"
  type        = string
  sensitive   = true
  default     = "moment-cf-secret-change-me"
}

# ─── WAF ───────────────────────────────────────────────────────────
variable "enable_waf" {
  description = "WAF Web ACL 생성 여부"
  type        = bool
  default     = true
}