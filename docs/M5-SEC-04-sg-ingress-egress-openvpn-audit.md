# M5-SEC-04 Security Group / Ingress / Egress / OpenVPN 접근 제어 점검

## 1. 개요

| 항목 | 내용 |
|---|---|
| 이슈 | M5-SEC-04 |
| 담당자 | @armddi |
| 수행 환경 | Dev/Network 중심 + Prod read-only |
| 수행 일자 | 2026-06-11 |
| 브랜치 | feature/m5-sec-04-sg-audit |

### 목표

CloudFront, ALB, EKS, RDS, Redis, OpenSearch, OpenVPN, VPC Endpoint 간 Security Group과 Ingress/Egress 접근 범위를 최소 허용 원칙에 맞게 점검한다.

---

## 2. TGW Route Table 점검

### Dev ↔ Prod 차단 확인

| Route Table | CIDR | 상태 | 설명 |
|---|---|---|---|
| moment-network-tgw-rt-dev | 10.10.0.0/16 | blackhole | Prod VPC 차단 ✅ |
| moment-network-tgw-rt-dev | 10.8.0.0/24 | active → network VPC | OpenVPN client CIDR ✅ |
| moment-network-tgw-rt-dev | 0.0.0.0/0 | active → network VPC | 인터넷 출구 ✅ |
| moment-network-tgw-rt-prod | 10.20.0.0/16 | blackhole | Dev VPC 차단 ✅ |
| moment-network-tgw-rt-prod | 10.8.0.0/24 | active → network VPC | OpenVPN client CIDR ✅ |
| moment-network-tgw-rt-prod | 0.0.0.0/0 | active → network VPC | 인터넷 출구 ✅ |

**결론: Dev ↔ Prod 상호 blackhole로 직접 통신 차단 확인 ✅**

### Private Data Route Table VPN CIDR return route 확인

| Route Table | CIDR | Target | 결과 |
|---|---|---|---|
| moment-dev-private-data-rt | 10.8.0.0/24 | TGW | ✅ |
| moment-prod-private-data-rt | 10.8.0.0/24 | TGW | ✅ |

### Network TGW subnet route table OpenVPN ENI route 확인

| Route Table | CIDR | Target | 결과 |
|---|---|---|---|
| moment-network-network-tgw-rt-1 | 10.8.0.0/24 | eni-0d2453fbb70333ea6 (OpenVPN ENI) | ✅ |
| moment-network-network-tgw-rt-1 | 0.0.0.0/0 | NAT GW | ✅ |
| moment-network-network-tgw-rt-2 | 10.8.0.0/24 | eni-0d2453fbb70333ea6 (OpenVPN ENI) | ✅ |
| moment-network-network-tgw-rt-2 | 0.0.0.0/0 | NAT GW | ✅ |

---

## 3. Security Group 점검 결과

### 3-1. ALB Security Group

| SG | Ingress | Egress | 결과 |
|---|---|---|---|
| moment-dev-alb-sg | 443 from CloudFront prefix list (pl-31a14458) | 8080 → dev-eks-node-sg | ✅ |
| moment-prod-alb-sg | 443 from CloudFront prefix list (pl-31a14458) | 8080 → prod-eks-node-sg | ✅ |

- CloudFront origin-facing prefix list 적용 확인 ✅
- 직접 ALB 접근 차단: CloudFront prefix list 기반 SG 제한 ✅

### 3-2. EKS Node Security Group

| SG | Ingress | Egress | 결과 |
|---|---|---|---|
| moment-dev-eks-node-sg | 8080 from dev-alb-sg, all from self | 5432→rds, 6379→redis, 443→opensearch+vpc-endpoint+0.0.0.0/0, all from self | ⚠️ |
| moment-prod-eks-node-sg | 8080 from prod-alb-sg, all from self | 5432→rds, 6379→redis, 443→opensearch+vpc-endpoint+0.0.0.0/0, all from self | ⚠️ |

- egress 443 0.0.0.0/0: NAT 경유 외부 HTTPS 트래픽용 (ECR pull, S3 등) → wide-open egress 목록 기록, 단계적 축소 검토 대상

### 3-3. EKS Cluster Security Group (auto-generated)

EKS가 자동 생성/관리하는 SG로 직접 수정 불가 → **제외 사유 기록**

### 3-4. Data Tier Security Group

| SG | Ingress | 결과 |
|---|---|---|
| moment-dev-rds-sg | 5432 from eks-node-sg, eks-cluster-sg, 10.8.0.0/24 | ✅ |
| moment-prod-rds-sg | 5432 from eks-node-sg, eks-cluster-sg, 10.8.0.0/24 | ✅ |
| moment-dev-redis-sg | 6379 from eks-node-sg, eks-cluster-sg, 10.8.0.0/24 | ✅ |
| moment-prod-redis-sg | 6379 from eks-node-sg, eks-cluster-sg, 10.8.0.0/24 | ✅ |
| moment-dev-opensearch-sg | 443 from eks-node-sg, eks-cluster-sg, 10.8.0.0/24 | ✅ |
| moment-prod-opensearch-sg | 443 from eks-node-sg, eks-cluster-sg, 10.8.0.0/24 | ✅ |

- Data Tier 0.0.0.0/0 inbound 없음 ✅
- EKS SG + OpenVPN Client CIDR(10.8.0.0/24)만 허용 ✅

### 3-5. VPC Endpoint Security Group

| SG | Ingress | 결과 |
|---|---|---|
| moment-dev-vpc-endpoint-sg | 443 from eks-node-sg, eks-cluster-sg | ✅ |
| moment-prod-vpc-endpoint-sg | 443 from eks-node-sg, eks-cluster-sg | ✅ |

### 3-6. OpenVPN Security Group

| SG | Ingress | Egress | 결과 |
|---|---|---|---|
| moment-network-openvpn-sg | UDP 1194 from 211.234.196.109/32 | all → 0.0.0.0/0 | ✅ |

- admin CIDR 제한 확인 ✅
- 점검 전 inbound 룰 누락 → Terraform apply로 복구 완료

---

## 4. 발견된 이슈 및 조치

### 이슈 1: OpenVPN SG inbound 룰 누락 (조치 완료)

| 항목 | 내용 |
|---|---|
| 심각도 | High |
| 원인 | admin_cidr_blocks 값이 tfvars에 있었으나 Terraform state에서 누락 |
| 영향 | OpenVPN 서버 클라이언트 접속 불가 |
| 조치 | terraform apply -target으로 inbound 룰 추가 완료 |
| 결과 | UDP 1194 from 211.234.196.109/32 정상 적용 확인 |

### 이슈 2: Dev VPC Endpoint SG eks-cluster-sg 룰 Description 누락 (기술 부채)

| 항목 | 내용 |
|---|---|
| 심각도 | Low |
| 원인 | 수동 추가된 룰, Terraform 미반영 |
| 조치 | Terraform 코드 반영 필요 (기술 부채 등록) |

### 이슈 3: EKS modules for_each 버그 (조치 완료)

| 항목 | 내용 |
|---|---|
| 심각도 | Medium |
| 원인 | aws_eks_access_policy_association for_each가 apply-time value 참조 |
| 조치 | for_each를 variable 기반 static value로 수정 완료 |

---

## 5. Wide-open Egress 목록

| SG | 룰 | 사유 | 판단 |
|---|---|---|---|
| moment-dev-eks-node-sg | tcp 443 → 0.0.0.0/0 | NAT 경유 ECR pull, S3, 외부 API 호출 필요 | 유지, 단계적 축소 검토 |
| moment-prod-eks-node-sg | tcp 443 → 0.0.0.0/0 | 동일 | 유지, 단계적 축소 검토 |
| moment-network-openvpn-sg | all → 0.0.0.0/0 | VPN 아웃바운드 특성상 필요 | 유지 |
| eks-cluster-sg (auto-generated) | all → 0.0.0.0/0 | EKS 관리형 SG, 수정 불가 | 제외 |

---

## 6. Terraform Plan 결과

| 환경 | 결과 |
|---|---|
| network | No changes ✅ |
| dev | 1 change (NAT GW route update, 정상) ✅ |
| prod | No changes ✅ |

의도치 않은 destroy/replacement 없음 확인 ✅

---

## 7. 완료 조건 체크리스트

- [x] Dev ALB Security Group 점검
- [x] Prod ALB Security Group 점검
- [x] ALB public inbound 범위 확인
- [x] HTTP/HTTPS listener 기준 확인
- [x] CloudFront origin-facing prefix list 적용 여부 확인
- [x] 직접 ALB 접근 차단 전략 확인
- [x] Dev EKS Node / Pod 관련 Security Group 점검
- [x] Prod EKS Node / Pod 관련 Security Group 점검
- [x] ALB -> EKS 허용 확인
- [x] EKS -> RDS 허용 확인
- [x] EKS -> Redis 허용 확인
- [x] EKS -> OpenSearch 허용 확인
- [x] RDS 5432 from EKS SG 확인
- [x] RDS 5432 from OpenVPN Client CIDR 확인
- [x] Redis 6379 from EKS SG 확인
- [x] Redis 6379 from OpenVPN Client CIDR 확인
- [x] OpenSearch 443 from EKS SG 확인
- [x] OpenSearch 443 from OpenVPN Client CIDR 확인
- [x] Data Tier 0.0.0.0/0 inbound 금지 확인
- [x] OpenVPN Security Group 관리자 CIDR 제한 확인
- [x] VPC Endpoint SG 443 from EKS/App subnet 기준 확인
- [x] TGW route table Dev <-> Prod 차단 확인
- [x] Private Data Route Table VPN CIDR return route 확인
- [x] Network TGW subnet route table OpenVPN ENI route 확인
- [x] 불필요한 wide-open egress 목록화
- [x] Terraform plan에서 의도치 않은 destroy/replacement 없음 확인
- [x] SG 점검 결과 문서 작성
