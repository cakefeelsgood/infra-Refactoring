# M5-SEC-03 AWS VPC CNI NetworkPolicy 적용 가능성 확인 및 Pod 통신 제어 구성

## 개요

EKS 내부 Pod 간 통신을 Namespace와 Workload 기준으로 제한하기 위해 NetworkPolicy를 GitOps로 적용한다.
AWS VPC CNI 환경에서는 NetworkPolicy YAML만 추가한다고 통신 제어가 되는 것이 아니므로,
VPC CNI version, addon configuration, node agent, policy enforcement 상태를 먼저 확인한다.

## CNI 확인 결과

| 항목 | 값 |
|------|-----|
| CNI Plugin | AWS VPC CNI |
| VPC CNI Version | v1.21.1-eksbuild.1 |
| NetworkPolicy 지원 | ✅ (v1.14+부터 지원) |
| enforcement 활성화 | ✅ NETWORK_POLICY_ENFORCING_MODE: standard |
| 적용 클러스터 | moment-prod-eks-cluster |

## NetworkPolicy 적용 범위

- **적용 Namespace**: `moment-prod`
- **미적용 Namespace**: `monitoring`, `argocd`, `external-secrets` (영향 범위 검토 후 별도 결정)

## Namespace Label 기준

| Namespace | 사용 Label |
|-----------|-----------|
| moment-prod | `kubernetes.io/metadata.name=moment-prod` |
| monitoring | `kubernetes.io/metadata.name=monitoring` |
| argocd | `kubernetes.io/metadata.name=argocd` |
| external-secrets | `kubernetes.io/metadata.name=external-secrets` |

## NetworkPolicy 구조

### 1. default-deny-all
`moment-prod` 네임스페이스의 모든 Ingress/Egress 기본 차단

### 2. allow-dns-egress
모든 Pod에서 CoreDNS(UDP/TCP 53)로의 DNS 쿼리 허용

### 3. allow-backend-api-ingress
ALB에서 backend-api(8080)로의 트래픽 허용

### 4. allow-backend-to-ai-service
backend-api에서 ai-service(8000)로의 트래픽 허용

### 5. allow-monitoring-scrape
monitoring 네임스페이스에서 모든 Pod의 metrics 수집 허용 (8080, 8000)

### 6. allow-alb-ingress
ALB에서 backend-api(8080)로의 헬스체크/트래픽 허용

## 서비스 간 통신 정책

| 출발 | 목적지 | 허용 여부 | 비고 |
|------|--------|----------|------|
| ALB | backend-api:8080 | ✅ | 외부 트래픽 |
| backend-api | ai-service:8000 | ✅ | 내부 통신 |
| backend-api | batch-job | ❌ | SQS polling 방식, 직접 통신 불필요 |
| monitoring | 모든 Pod | ✅ | metrics scrape |
| 모든 Pod | CoreDNS:53 | ✅ | DNS 필수 |

## ArgoCD / External Secrets / ALB Controller 영향 검토

- **ArgoCD**: Kubernetes API server 통해 리소스 배포 → NetworkPolicy 영향 없음
- **External Secrets**: Kubernetes API server 통해 Secret 생성 → NetworkPolicy 영향 없음
- **ALB Controller**: ALB → Pod 트래픽은 allow-alb-ingress로 허용

## Prod 적용 현황

- vpc-cni enforcement 활성화 완료
  - **정정(2026-10-23):** `terraform/modules/eks`가 addon `configuration_values`를 전달하지 않아 `enableNetworkPolicy=true`는 코드상으로 적용되지 않은 상태였다. 콘솔 수동 적용 여부는 코드로 알 수 없다. 모듈 수정 후 다음 apply부터 실제로 반영된다([eks.md](eks.md) Add-on 구성).
- NetworkPolicy manifest 작성 완료
- ArgoCD sync는 Dev 검증 완료 후 수행 예정

## Dev 검증 계획

1. Dev ArgoCD 설치 후 network-policy-dev sync
2. `kubectl run netshoot`으로 차단 테스트
3. backend-api → ai-service 허용 테스트
4. DNS 쿼리 허용 테스트
5. 검증 완료 후 Prod sync 진행
