# MoMent Terraform 인프라

## 개요

MoMent 프로젝트의 AWS 인프라를 Terraform으로 관리합니다.
Primary Region은 `ap-northeast-3` (Osaka)를 사용합니다.

## 디렉토리 구조
```
terraform/
├── environments/
│   └── dev/
│       ├── main.tf                  # locals (공통 태그)
│       ├── provider.tf              # AWS provider 설정
│       ├── variables.tf             # 공통 변수 정의
│       ├── outputs.tf               # 출력값
│       └── terraform.tfvars.example # 변수 예시
│
└── modules/
├── network-vpc/     # Network VPC
├── prod-vpc/        # Prod VPC
├── dev-vpc/         # Dev VPC
├── transit-gateway/
├── security-group/
├── vpc-endpoint/
├── ecr/
├── eks/
├── rds/
├── redis/
├── opensearch/
├── sqs/
├── s3/
├── profile-image-bucket/
└── data-pipeline/
```

## VPC 구조

| VPC | CIDR | 용도 |
|-----|------|------|
| Network VPC | 10.0.0.0/16 | 공통 네트워크 (NAT, IGW 등) |
| Prod VPC | 10.10.0.0/16 | 운영 환경 |
| Dev VPC | 10.20.0.0/16 | 개발 환경 |

## Provider

| Provider | Region | 용도 |
|----------|--------|------|
| aws (default) | ap-northeast-3 | 기본 리소스 |
| aws.use1 | us-east-1 | CloudFront ACM 인증서 |

## 공통 태그

모든 리소스에 아래 태그가 자동 적용됩니다.

| Key | Value |
|-----|-------|
| Project | moment |
| Environment | dev / prod |
| ManagedBy | terraform |
| Owner | team04 |

## 주요 문서

| 문서 | 설명 |
| --- | --- |
| docs/sqs.md | SQS + DLQ 구성, Dev/Prod 활성화 정책, IAM 연결 기준 |
| docs/s3-raw-bucket.md | S3 Raw Bucket Dev/Prod 분리 기준 및 Shared Raw Bucket 정리 기준 |
| docs/profile-image-bucket.md | 프로필 이미지 업로드용 S3 Bucket, CORS, Backend 권한 연결 기준 |
| docs/notification-sns.md | SNS 알림 발송용 Topic, Backend Publish 권한, Dev/Prod 활성화 정책 |
| docs/alb-controller.md | AWS Load Balancer Controller 설치, Dev 검증, Prod 활성화 절차 |
| docs/data-pipeline.md | EventBridge Scheduler + Lambda Collector 데이터 파이프라인 구성 및 Dev/Prod 활성화 정책 |
| docs/rds.md | RDS PostgreSQL Dev/Prod 스펙 분리 및 Prod 보호 옵션 기준 |
| docs/opensearch.md | OpenSearch Dev/Prod 스펙 분리 및 Prod HA 옵션 기준 |
| docs/karpenter.md | Karpenter On-Demand + Spot 혼합 운영, base/burst 분할 웹훅, 적용 순서 |
| docs/runbooks/vpc-cni-prefix-delegation.md | VPC CNI Prefix Delegation과 maxPods 정합성, 서브넷 /28 확인 절차 |
| docs/terraform-environments.md | Dev/Prod Terraform environment 및 state 분리 전략 |
| docs/gitops.md | GitOps Repository 구조, Helm Chart/Values 경로, ArgoCD Application 경로 기준 |
| docs/argocd.md | Dev ArgoCD 설치, 접근 방식, repo 연결 및 보안 정리 기준 |
| docs/m2-close-checklist.md | M2 Infra Bootstrap 최종 완료 체크리스트 및 M3 인수인계 기준 |
| docs/m2-valid-b-runbook.md | Network / TGW / Data / IAM / Destroy 검증 및 운영 Runbook |

## 시작하기

```bash
cd terraform/environments/dev

cp terraform.tfvars.example terraform.tfvars
# terraform.tfvars 값 수정 후

terraform init
terraform fmt -recursive
terraform validate
terraform plan
```

---
## EKS Managed NodeGroup 분리 기준

> **2026-10-23 변경:** batch/ai 워크로드는 Karpenter NodePool로 옮기고, 기존 batch/ai 노드그룹은 이전이 끝난 뒤 `enable_<env>_legacy_workload_nodegroups = false`로 제거한다(최종적으로 core/ops만 남음). 현재 구성은 [docs/karpenter.md](docs/karpenter.md)를 기준으로 한다. 아래는 이전 기준이다.

MoMent Dev EKS 환경은 워크로드 특성에 따라 On-Demand NodeGroup과 Spot NodeGroup을 분리하여 구성한다.

### 1. Core On-Demand NodeGroup

- NodeGroup: `moment-dev-core-on-demand-ng`
- capacity type: `ON_DEMAND`
- label:
  - `workload=core`
  - `capacity=on-demand`
- 기본 desired size: `1`

Core NodeGroup은 서비스의 핵심 요청을 처리하는 안정성 우선 워크로드를 배치하기 위한 NodeGroup이다.

배치 대상은 다음과 같다.

- Backend API
- 인증/인가 요청 처리
- 결제 및 예약 요청 처리
- 사용자 요청 기반의 실시간 API 처리

위 워크로드는 중단 시 사용자 경험에 직접적인 영향을 줄 수 있으므로 Spot이 아닌 On-Demand NodeGroup에 배치한다.

예시 배치 기준:

```yaml
nodeSelector:
  workload: core
  capacity: on-demand
```

---

### 2. Batch Spot NodeGroup

- NodeGroup: `moment-dev-batch-spot-ng`
- capacity type: `SPOT`
- label:
  - `workload=batch`
  - `capacity=spot`
- 기본 desired size: `0`

Batch Spot NodeGroup은 중단되어도 재시도 가능한 비핵심 작업을 처리하기 위한 NodeGroup이다.

배치 대상은 다음과 같다.

- 공공데이터 수집 Batch Job
- 데이터 정제 작업
- 실패 시 재시도 가능한 비동기 작업
- 예약된 데이터 적재 작업

Spot NodeGroup은 비용 절감을 목적으로 사용하며, Spot 중단 가능성을 전제로 Job 재시도 정책을 함께 고려한다.

예시 배치 기준:

```yaml
nodeSelector:
  workload: batch
  capacity: spot

tolerations:
  - key: "workload"
    operator: "Equal"
    value: "batch"
    effect: "NoSchedule"
```

---

### 3. AI Spot NodeGroup

- NodeGroup: `moment-dev-ai-spot-ng`
- capacity type: `SPOT`
- label:
  - `workload=ai`
  - `capacity=spot`
- 기본 desired size: `0`

AI Spot NodeGroup은 AI 관련 비동기 작업 또는 재시도 가능한 추천/검색 처리 작업을 배치하기 위한 NodeGroup이다.

배치 대상은 다음과 같다.

- AI 추천 설명 생성
- 검색 인덱싱 작업
- Embedding 생성 작업
- 비동기 AI 처리 워크로드

AI 작업은 비용 부담이 커질 수 있으므로 기본적으로 Spot NodeGroup에 배치하되, 실시간성이 강한 요청은 Backend API에서 처리하고 무거운 작업은 비동기로 분리한다.

예시 배치 기준:

```yaml
nodeSelector:
  workload: ai
  capacity: spot

tolerations:
  - key: "workload"
    operator: "Equal"
    value: "ai"
    effect: "NoSchedule"
```

---

### 4. Ops NodeGroup

- NodeGroup: `moment-dev-ops-on-demand-ng`
- capacity type: `ON_DEMAND`
- label:
  - `workload=ops`
  - `capacity=on-demand`
- 기본 desired size: `0`

Ops NodeGroup은 운영 도구를 분리 배치하기 위한 NodeGroup이다.

배치 대상은 다음과 같다.

- ArgoCD
- Prometheus
- Grafana
- Loki
- 기타 운영 및 모니터링 도구

운영 도구는 서비스 워크로드와 분리하여 장애 영향 범위를 줄이는 것을 목표로 한다.

예시 배치 기준:

```yaml
nodeSelector:
  workload: ops

tolerations:
  - key: "workload"
    operator: "Equal"
    value: "ops"
    effect: "NoSchedule"
```

---

## Dev / Prod NodeGroup 활성화 정책

MoMent Terraform 구성에서는 Dev 환경을 기본 검증 대상으로 설정하고, Prod NodeGroup은 명시적으로 활성화한 경우에만 생성되도록 구성한다.

기본 정책은 다음과 같다.

- Dev EKS Cluster: 활성화
- Dev NodeGroup: 활성화
- Prod EKS Cluster: 기본 비활성화
- Prod NodeGroup: 기본 비활성화

Prod NodeGroup은 운영 배포 검증 또는 최종 시연 시점에만 명시적으로 활성화한다.

예시:

```hcl
enable_dev_eks        = true
enable_dev_nodegroups = true

enable_prod_eks        = false
enable_prod_nodegroups = false
```

Prod NodeGroup을 생성해야 하는 경우에만 다음과 같이 변경한다.

```hcl
enable_prod_eks        = true
enable_prod_nodegroups = true
```

이를 통해 개발 중 불필요한 운영 환경 비용을 줄이고, Dev 환경 중심으로 NodeGroup 구성과 배치 전략을 먼저 검증한다.

---

## Spot NodeGroup 운영 전제

Spot NodeGroup은 비용 절감을 위해 사용하지만, AWS에 의해 언제든 중단될 수 있다.

따라서 Spot NodeGroup에는 다음 조건을 만족하는 워크로드만 배치한다.

- 중단되어도 사용자 요청에 직접적인 장애를 주지 않는 작업
- 실패 후 재시도 가능한 작업
- Batch Job 또는 비동기 처리 작업
- 처리 지연은 허용되지만 비용 최적화가 중요한 작업

반대로 다음 워크로드는 Spot NodeGroup에 배치하지 않는다.

- 사용자 실시간 요청 처리
- 인증/인가
- 결제/예약 처리
- 핵심 Backend API

---

## 검증 결과

Dev EKS 환경에서 Managed NodeGroup 생성 및 기본 Add-on 정상화를 확인했다.

검증 명령어:

```bash
kubectl get nodes -L workload,capacity
```

확인 결과:

- Core NodeGroup 노드가 `Ready` 상태로 등록됨
- `workload=core` 라벨 확인
- `capacity=on-demand` 라벨 확인

Add-on 상태 확인:

```bash
for addon in vpc-cni coredns kube-proxy aws-ebs-csi-driver; do
  aws eks describe-addon \
    --region ap-northeast-3 \
    --cluster-name moment-dev-eks-cluster \
    --addon-name $addon \
    --query "addon.{name:addonName,status:status,health:health}" \
    --output json
done
```

확인 결과:

- `vpc-cni`: ACTIVE
- `coredns`: ACTIVE
- `kube-proxy`: ACTIVE
- `aws-ebs-csi-driver`: ACTIVE
---
# EKS Managed NodeGroup 구성 및 워크로드 배치 기준

## 1. 구성 목적

MoMent Dev EKS 환경에서는 워크로드의 중요도와 중단 허용 여부에 따라 Managed NodeGroup을 분리하여 구성한다.

핵심 사용자 요청을 처리하는 워크로드는 안정성을 우선하여 On-Demand NodeGroup에 배치하고, 중단되어도 재시도 가능한 Batch / AI 비동기 작업은 비용 최적화를 위해 Spot NodeGroup에 배치한다.

이를 통해 다음 목적을 달성한다.

- 핵심 서비스 워크로드 안정성 확보
- Batch / AI 작업 비용 최적화
- 워크로드별 장애 영향 범위 분리
- Dev 환경 중심 검증 후 Prod 환경 선택적 확장

---

## 2. Dev / Prod NodeGroup 활성화 정책

현재 Terraform 구성에서는 Dev EKS Cluster와 Dev NodeGroup을 기본 생성 대상으로 사용한다.

Prod EKS 및 Prod NodeGroup은 기본적으로 비활성화하며, 운영 검증 또는 최종 배포가 필요한 경우에만 명시적으로 활성화한다.

### 기본 정책

| 환경 | EKS Cluster | NodeGroup | 기본 상태 |
|---|---|---|---|
| Dev | 생성 | 생성 | 활성화 |
| Prod | 미생성 | 미생성 | 비활성화 |

### 예시 설정

```hcl
enable_dev_eks        = true
enable_dev_nodegroups = true

enable_prod_eks        = false
enable_prod_nodegroups = false
```

Prod 환경 NodeGroup이 필요한 경우에만 다음과 같이 명시적으로 활성화한다.

```hcl
enable_prod_eks        = true
enable_prod_nodegroups = true
```

현재 검증에서는 Dev NodeGroup만 생성되며, Prod NodeGroup은 생성되지 않도록 구성했다.

---

## 3. NodeGroup 구성

## 3.1 Core On-Demand NodeGroup

| 항목 | 값 |
|---|---|
| NodeGroup | `moment-dev-core-on-demand-ng` |
| capacity type | `ON_DEMAND` |
| label | `workload=core` |
| label | `capacity=on-demand` |
| desired size | `1` |

Core On-Demand NodeGroup은 서비스의 핵심 요청을 처리하는 워크로드를 배치하기 위한 NodeGroup이다.

### 배치 대상

- Backend API
- 인증 / 인가 요청 처리
- 결제 / 예약 요청 처리
- 사용자 요청 기반 실시간 API
- 중단 시 사용자 경험에 직접 영향을 주는 핵심 서비스

### 배치 기준 예시

```yaml
nodeSelector:
  workload: core
  capacity: on-demand
```

---

## 3.2 Batch Spot NodeGroup

| 항목 | 값 |
|---|---|
| NodeGroup | `moment-dev-batch-spot-ng` |
| capacity type | `SPOT` |
| label | `workload=batch` |
| label | `capacity=spot` |
| desired size | `0` 또는 테스트 시 `1` |

Batch Spot NodeGroup은 중단되어도 재시도 가능한 데이터 처리 작업을 배치하기 위한 NodeGroup이다.

### 배치 대상

- 공공데이터 수집 Batch Job
- 데이터 정제 작업
- 실패 후 재시도 가능한 비동기 작업
- 예약 기반 데이터 적재 작업

### 배치 기준 예시

```yaml
nodeSelector:
  workload: batch
  capacity: spot

tolerations:
  - key: "workload"
    operator: "Equal"
    value: "batch"
    effect: "NoSchedule"
```

Spot NodeGroup은 비용 절감을 목적으로 사용하며, AWS에 의해 중단될 수 있으므로 Batch Job은 재시도 가능한 구조를 전제로 한다.

---

## 3.3 AI Spot NodeGroup

| 항목 | 값 |
|---|---|
| NodeGroup | `moment-dev-ai-spot-ng` |
| capacity type | `SPOT` |
| label | `workload=ai` |
| label | `capacity=spot` |
| desired size | `0` 또는 테스트 시 `1` |

AI Spot NodeGroup은 AI 관련 비동기 처리 작업을 배치하기 위한 NodeGroup이다.

### 배치 대상

- AI 추천 설명 생성
- 검색 인덱싱 작업
- Embedding 생성 작업
- 비동기 AI 처리 작업

AI 작업은 비용 부담이 커질 수 있으므로 기본적으로 Spot NodeGroup에 배치한다. 단, 사용자 요청과 직접 연결되는 실시간 API 처리는 Core On-Demand NodeGroup에서 처리하고, 무거운 AI 작업은 비동기 처리로 분리한다.

### 배치 기준 예시

```yaml
nodeSelector:
  workload: ai
  capacity: spot

tolerations:
  - key: "workload"
    operator: "Equal"
    value: "ai"
    effect: "NoSchedule"
```

---

## 3.4 Ops NodeGroup

| 항목 | 값 |
|---|---|
| NodeGroup | `moment-dev-ops-on-demand-ng` |
| capacity type | `ON_DEMAND` |
| label | `workload=ops` |
| label | `capacity=on-demand` |
| desired size | `0` |

Ops NodeGroup은 운영 도구를 서비스 워크로드와 분리 배치하기 위한 NodeGroup이다.

### 배치 대상

- ArgoCD
- Prometheus
- Grafana
- Loki
- 기타 운영 / 모니터링 도구

운영 도구를 별도 NodeGroup에 배치하면 서비스 워크로드와 운영 워크로드의 영향 범위를 분리할 수 있다.

### 배치 기준 예시

```yaml
nodeSelector:
  workload: ops

tolerations:
  - key: "workload"
    operator: "Equal"
    value: "ops"
    effect: "NoSchedule"
```

---

## 4. Spot NodeGroup 운영 전제

Spot NodeGroup은 비용 절감을 위해 사용하지만, AWS에 의해 언제든 중단될 수 있다.

따라서 Spot NodeGroup에는 다음 조건을 만족하는 워크로드만 배치한다.

- 중단되어도 사용자 요청에 직접적인 장애를 주지 않는 작업
- 실패 후 재시도 가능한 작업
- Batch Job 또는 비동기 처리 작업
- 처리 지연은 허용되지만 비용 최적화가 중요한 작업

반대로 다음 워크로드는 Spot NodeGroup에 배치하지 않는다.

- 사용자 실시간 요청 처리
- 인증 / 인가 처리
- 결제 / 예약 처리
- 핵심 Backend API

---

## 5. 검증 결과

## 5.1 NodeGroup ACTIVE 확인

Terraform apply 결과 Dev EKS NodeGroup이 모두 ACTIVE 상태로 생성되었다.

확인된 NodeGroup은 다음과 같다.

| NodeGroup | 용도 | 상태 |
|---|---|---|
| `moment-dev-core-on-demand-ng` | 핵심 서비스 워크로드 | ACTIVE |
| `moment-dev-batch-spot-ng` | Batch Job 워크로드 | ACTIVE |
| `moment-dev-ai-spot-ng` | AI 비동기 워크로드 | ACTIVE |
| `moment-dev-ops-on-demand-ng` | 운영 도구 워크로드 | ACTIVE |

---

## 5.2 Kubernetes Node Label 확인

다음 명령어로 NodeGroup 라벨을 확인했다.

```bash
kubectl get nodes -L workload,capacity
```

확인 결과 Core On-Demand NodeGroup 노드가 Ready 상태로 등록되었고, 다음 라벨이 적용되어 있었다.

- `workload=core`
- `capacity=on-demand`

---

## 5.3 Core Add-on 상태 확인

다음 EKS Add-on이 모두 ACTIVE 상태임을 확인했다.

| Add-on | 상태 |
|---|---|
| `vpc-cni` | ACTIVE |
| `coredns` | ACTIVE |
| `kube-proxy` | ACTIVE |
| `aws-ebs-csi-driver` | ACTIVE |

---

## 5.4 Spot NodeGroup 테스트 Pod 배치 확인

Batch Spot NodeGroup의 desired size를 테스트 시점에만 1로 조정한 뒤, 비핵심 테스트 Pod를 배치했다.

테스트 결과 `batch-test` Pod가 다음 노드에 정상 배치되었다.

- Node label: `workload=batch`
- Node label: `capacity=spot`
- Pod status: `Running`

검증 후 비용 절감을 위해 Batch Spot NodeGroup의 desired size를 다시 0으로 조정했다.

---

## 5.5 Backend API 테스트 Pod 배치 확인

핵심 Backend API 테스트 Pod를 Core On-Demand NodeGroup에 배치했다.

테스트 Pod 생성 시 다음 nodeSelector를 사용했다.

```yaml
nodeSelector:
  workload: core
  capacity: on-demand
```

확인 결과 `backend-api-test` Pod가 Core On-Demand 노드에 정상 배치되었다.

- Pod status: `Running`
- Node label: `workload=core`
- Node label: `capacity=on-demand`

이를 통해 핵심 서비스 워크로드가 On-Demand NodeGroup에 배치되는 것을 확인했다.

---

## 6. 최종 정리

이번 작업을 통해 Dev EKS 환경에서 Managed NodeGroup을 워크로드 특성별로 분리 구성했다.

- 핵심 Backend API는 On-Demand NodeGroup에 배치
- Batch / AI 작업은 Spot NodeGroup에 배치 가능하도록 구성
- Ops 도구는 별도 NodeGroup으로 분리 가능하도록 구성
- Prod NodeGroup은 기본 비활성화하여 불필요한 비용 발생 방지
- Add-on 및 NodeGroup ACTIVE 상태 확인
- 테스트 Pod를 통해 nodeSelector 기반 배치 검증 완료
## 운영 Runbook

- [M2-VALID-A App / EKS / Ingress / Endpoint / Edge 검증 및 운영 Runbook](docs/M2-VALID-A-Runbook.md)
