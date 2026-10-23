# Edge Layer 구성 가이드
 
> 관련 이슈: M2-EDGE-01, M2-EDGE-02
> 담당: @armddi
 
---
 
## 아키텍처 흐름
 
```
User
│
▼
Route53 (선택)
│  DNS 조회 → CloudFront 도메인
▼
CloudFront Distribution
│  ├─ WAF Web ACL (AWSManagedRules 3종)
│  ├─ ACM 인증서 (us-east-1, HTTPS 강제)
│  └─ Origin: Prod ALB (Custom Header 포함)
▼
Prod VPC Public Subnet — ALB
│  └─ X-CloudFront-Secret 헤더 검증 (향후 ALB WAF Rule)
▼
EKS (moment-prod-eks-cluster)
├─ RDS (PostgreSQL)
├─ Redis (ElastiCache)
└─ OpenSearch
```
 
---
 
## 주요 리소스
 
| 리소스 | 위치 | 설명 |
|---|---|---|
| CloudFront Distribution | Global | CDN + HTTPS 진입점 |
| WAF Web ACL | us-east-1 (CLOUDFRONT scope) | 공통 웹 공격 방어 |
| ACM 인증서 | us-east-1 | CloudFront 전용 (커스텀 도메인 시) |
| Route53 Hosted Zone | Global (선택) | DNS 관리 |
 
---
 
## 설계 결정 사항
 
### ALB Origin 활성화 조건 (M2-EDGE-02)
 
`enable_edge = true` 상태에서 `prod_alb_dns_name = ""`이면 **plan 단계에서 실패**한다.
 
```
│ Error: Resource precondition failed
│
│ alb_dns_name이 비어 있습니다. Prod ALB 구성 완료 후
│ prod_alb_dns_name 변수를 설정하세요.
```
 
이는 `modules/edge/main.tf`의 `aws_cloudfront_distribution` 리소스에 `precondition`으로 구현되어 있다.
 
```hcl
lifecycle {
  precondition {
    condition     = var.alb_dns_name != null && var.alb_dns_name != ""
    error_message = "alb_dns_name이 비어 있습니다..."
  }
}
```
 
> ⚠️ ALB Controller / Kubernetes Ingress 구성이 완료되기 전에는 Edge 실제 연결 검증이 제한된다.
> ALB DNS가 확정된 후 `prod_alb_dns_name` 변수를 채우고 plan/apply 진행한다.
 
---
 
### Route53 Hosted Zone 사용 기준
 
| 상황 | 설정 |
|------|------|
| 도메인 없음 | `edge_domain_name = ""` → CloudFront 기본 도메인(`xxxx.cloudfront.net`) 사용 |
| 도메인 신규 생성 | `create_route53_hosted_zone = true` |
| 도메인 기존 보유 | `create_route53_hosted_zone = false` → 기존 Zone 조회 |
 
---
 
### ACM 인증서 (us-east-1) 사용 기준
 
- CloudFront에 연결되는 ACM 인증서는 **반드시 us-east-1**에 생성해야 한다.
- ap-northeast-3(오사카) 리전 인증서는 CloudFront에 사용 불가.
- `providers = { aws.us_east_1 = aws.us_east_1 }` 로 provider alias 전달.
- 커스텀 도메인 없을 경우(`edge_domain_name = ""`) ACM 인증서는 생성되지 않는다.
---
 
### CloudFront → ALB 접근 제한 전략
 
직접 ALB 접근 차단을 위해 아래 3가지 전략을 계층적으로 적용한다.
 
#### 1. Custom Secret Header (현재 적용)
 
CloudFront가 ALB로 요청 시 `X-CloudFront-Secret` 헤더를 자동 삽입한다.
 
```
CloudFront → X-CloudFront-Secret: <secret> → ALB
```
 
- Secret 값은 `cloudfront_secret_header_value` 변수로 관리 (sensitive)
- ALB Listener Rule 또는 WAF에서 헤더 없는 요청 차단 (후속 적용)
#### 2. CloudFront Managed Prefix List (후속 적용 권장)
 
AWS에서 제공하는 CloudFront Origin-Facing IP 범위를 ALB SG 인바운드 룰에 적용한다.
 
```hcl
# ALB SG 인바운드 예시
ingress {
  from_port       = 80
  to_port         = 80
  protocol        = "tcp"
  prefix_list_ids = ["pl-58a04531"]  # com.amazonaws.global.cloudfront.origin-facing
}
```
 
> Prefix List ID `pl-58a04531`은 ap-northeast-3 기준 CloudFront Origin-Facing IP 범위다.
> ALB SG에 적용하면 CloudFront를 통하지 않는 직접 접근을 차단할 수 있다.
 
#### 3. ALB SG 제한 (후속 적용)
 
ALB SG 인바운드를 CloudFront Prefix List로만 제한하면 Secret Header 없이도 직접 접근이 불가능해진다. Secret Header와 병행 사용 시 이중 보호가 된다.
 
---
 
### WAF Web ACL 연결 확인
 
WAF Web ACL은 CloudFront Distribution의 `web_acl_id`로 연결된다.
 
```hcl
web_acl_id = var.enable_waf ? aws_wafv2_web_acl.cloudfront[0].arn : null
```
 
현재 적용된 Managed Rule:
 
| Rule | 우선순위 | 목적 |
|------|----------|------|
| AWSManagedRulesCommonRuleSet | 10 | SQLi, XSS 등 OWASP Top 10 방어 |
| AWSManagedRulesKnownBadInputsRuleSet | 20 | 알려진 악성 패턴 차단 |
| AWSManagedRulesAmazonIpReputationList | 30 | 봇·DDoS 소스 IP 차단 |
 
> WAF는 `scope = "CLOUDFRONT"`로 **반드시 us-east-1**에 생성해야 한다.
 
---
 
### ALB Origin HTTPS 여부
 
- 현재: `prod_alb_https_enabled = false` (HTTP 80 → ALB)
- Prod ALB에 ap-northeast-3용 ACM 인증서 연결 후 `true`로 변경
- CloudFront → ALB 구간 HTTPS 전환은 ALB Listener 443 구성 완료 후 진행
---
 
## Edge 활성화 전 체크리스트
 
실제 apply 전 아래 항목이 모두 준비되어야 한다.
 
| 항목 | 확인 |
|------|------|
| Prod ALB 생성 및 DNS 확정 | `prod_alb_dns_name` 값 확보 |
| ALB Controller 설치 완료 (M2-EKS-03) | Ingress → ALB 연결 |
| Kubernetes Ingress 생성 완료 | ALB Listener Rule 확인 |
| `cloudfront_secret_header_value` 변경 | 기본값 `moment-cf-secret-change-me` 반드시 교체 |
| ALB SG에 CloudFront Prefix List 적용 | 직접 접근 차단 |
 
---
 
## 운영 절차
 
### Prod ALB 연동 (ALB 구성 완료 후)
 
```bash
# terraform/environments/prod/terraform.tfvars 수정
prod_alb_dns_name      = "<prod-alb-dns>.ap-northeast-3.elb.amazonaws.com"
prod_alb_https_enabled = false   # ALB HTTPS 준비되면 true
 
# Redis만 타겟 apply와 동일하게 Edge만 apply
cd terraform/environments/prod
terraform apply -target=module.edge
```
 
### Secret Header 갱신
 
```bash
# terraform.tfvars에서 값 변경 후 apply
cloudfront_secret_header_value = "new-secret-$(date +%Y%m)"
terraform apply -target=module.edge
```
 
### CloudFront 캐시 무효화
 
```bash
aws cloudfront create-invalidation \
  --distribution-id <distribution-id> \
  --paths "/*"
```
 
---
 
## outputs 참조
 
```bash
terraform output cloudfront_domain_name   # 접속 URL
terraform output waf_web_acl_id           # WAF ACL ID
terraform output acm_certificate_arn      # ACM ARN (도메인 있을 때만)
terraform output cloudfront_secret_header_name  # X-CloudFront-Secret
```
## Edge 연결 완료 (2026-06-07)

- CloudFront Origin: k8s-momentpr-backenda-23baa3cdfd-1074547664.ap-northeast-3.elb.amazonaws.com
- ACM 인증서: api.moment-team04.click (ISSUED, us-east-1)
- Route53: api.moment-team04.click A 레코드 → CloudFront
- WAF Web ACL 연결 완료
- 검증: curl https://api.moment-team04.click/health → MoMent backend is running
