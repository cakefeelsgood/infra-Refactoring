# EKS Cluster 구성

## 목적

M2-EKS-01 범위에서 MoMent EKS Cluster와 기본 Add-on 구성을 Terraform으로 관리한다.

이번 구성은 EKS 공통 모듈, Dev EKS Cluster 기본 활성화, Prod EKS Cluster 선택 활성화 구조를 포함한다.

실습/검증은 비용 절감을 위해 Dev EKS에서 진행하고, Prod EKS는 운영 기간 또는 최종 시연 시점에만 명시적으로 활성화한다.

## 기본 활성화 정책

| 항목 | 기본값 | 설명 |
| --- | --- | --- |
| `enable_dev_eks` | `true` | Dev EKS를 기본 생성하여 실습/검증에 사용 |
| `enable_prod_eks` | `false` | Prod EKS는 비용 절감을 위해 기본 미생성 |

기본 Terraform plan/apply에서는 Dev EKS만 생성되어야 한다.

Prod EKS는 다음처럼 명시적으로 활성화한 경우에만 생성한다.

```bash
-var='enable_prod_eks=true'
```

## 범위

### 포함

- EKS 공통 Terraform 모듈 생성
- Dev EKS Cluster 기본 활성화
- Prod EKS Cluster 선택 활성화 구조
- Kubernetes version 명시
- EKS Cluster IAM Role 연결
- EKS API Endpoint 접근 설정
- EKS Access Entry 기반 관리자 접근 설정
- EKS OIDC Provider 생성
- 기본 EKS managed Add-on 구성
  - VPC CNI
  - CoreDNS
  - kube-proxy
  - AWS EBS CSI Driver
- AWS EBS CSI Driver용 IRSA Role 구성
- Terraform outputs 구성

### 제외

다음 항목은 M2-EKS-01 범위가 아니며, 별도 이슈에서 처리한다.

- EKS Managed NodeGroup 생성
- On-Demand / Spot NodeGroup 분리
- Workload label / taint 기반 배치 정책
- Kubernetes Deployment / Service / Ingress 생성
- AWS Load Balancer Controller 설치
- ALB / Target Group / Listener 생성

특히 `aws_eks_node_group` 리소스는 M2-EKS-02 범위이므로 이번 PR에서 생성하지 않는다.

## Terraform 구성

EKS 모듈 경로는 다음과 같다.

```text
terraform/modules/eks
```

Root module 경로는 다음과 같다.

```text
terraform/environments/dev
```

주요 리소스는 다음과 같다.

```text
aws_eks_cluster
aws_eks_access_entry
aws_eks_access_policy_association
aws_iam_openid_connect_provider
aws_iam_role
aws_iam_role_policy_attachment
aws_eks_addon
```

## Cluster 설정

### Dev EKS

| 항목 | 값 |
| --- | --- |
| Cluster Name | moment-dev-eks-cluster |
| Kubernetes Version | 1.35 |
| VPC | Dev VPC |
| Subnet | Dev Private App Subnets |
| Endpoint Private Access | true |
| Endpoint Public Access | true |
| Authentication Mode | API |
| 기본 활성화 | true |

### Prod EKS

| 항목 | 값 |
| --- | --- |
| Cluster Name | moment-prod-eks-cluster |
| Kubernetes Version | 1.35 |
| VPC | Prod VPC |
| Subnet | Prod Private App Subnets |
| Endpoint Private Access | true |
| Endpoint Public Access | true |
| Authentication Mode | API |
| 기본 활성화 | false |

EKS API public endpoint는 제한된 CIDR에서만 접근하도록 구성한다.

기본값은 기존 admin CIDR을 사용한다.

```text
115.138.87.55/32
```

작업자의 현재 공인 IP가 다르면 Terraform plan/apply 시 다음 변수로 override 한다.

```bash
-var='dev_eks_public_access_cidrs=["<현재-public-ip>/32"]'
```

Prod EKS를 명시적으로 활성화하는 경우에는 다음 변수도 같이 override 할 수 있다.

```bash
-var='prod_eks_public_access_cidrs=["<현재-public-ip>/32"]'
```

## Add-on 구성

| Add-on | Version |
| --- | --- |
| vpc-cni | v1.21.1-eksbuild.1 |
| coredns | v1.13.2-eksbuild.4 |
| kube-proxy | v1.35.3-eksbuild.2 |
| aws-ebs-csi-driver | v1.60.0-eksbuild.1 |

vpc-cni `configuration_values` (2026-10-23):

| 키 | 값 | 근거 |
| --- | --- | --- |
| `enableNetworkPolicy` | `"true"` | M5-SEC-03. 이전에는 `modules/eks`가 이 값을 전달하지 못했다(아래 주의) |
| `env.ENABLE_PREFIX_DELEGATION` | `"true"` | VPC CNI 실험. kubelet `maxPods: 40`과 한 묶음 ([런북](runbooks/vpc-cni-prefix-delegation.md)) |
| `env.WARM_IP_TARGET` / `env.MINIMUM_IP_TARGET` | `"1"` / `"3"` | PD의 prefix 선점을 줄인다(실험에서 서브넷 소비 +19% → +7%) |

> 주의: 2026-10-23 이전 `modules/eks`의 addons 타입에 `configuration_values`가 없어서, `main.tf`에 적힌 `enableNetworkPolicy`가 Terraform 타입 변환에서 버려지고 있었다. 수정 후 처음 apply할 때 실제 설정이 바뀐다.

AWS EBS CSI Driver는 전용 IRSA Role을 사용한다.

ServiceAccount subject는 다음과 같다.

```text
system:serviceaccount:kube-system:ebs-csi-controller-sa
```

연결 policy는 AWS managed policy를 사용한다.

```text
arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy
```

## NodeGroup 관련 주의사항

M2-EKS-01에서는 EKS Cluster와 기본 Add-on까지만 구성한다.

Managed NodeGroup은 M2-EKS-02 범위이므로 이번 Terraform plan에 다음 리소스가 포함되면 안 된다.

```text
aws_eks_node_group
aws_launch_template
aws_autoscaling_group
helm_release
kubernetes_deployment
kubernetes_service
kubernetes_ingress
aws_lb
aws_lb_listener
aws_lb_target_group
```

NodeGroup이 아직 없으면 `kubectl get nodes` 결과는 노드가 없는 상태로 나올 수 있다.

CoreDNS 등 일부 Add-on Pod는 NodeGroup 생성 전까지 Pending 또는 미스케줄 상태일 수 있다.

실제 Worker Node 생성과 On-Demand / Spot 분리는 M2-EKS-02에서 진행한다.

## 검증 명령

Terraform 검증은 다음 순서로 수행한다.

```bash
terraform -chdir=terraform/environments/dev fmt -check -recursive
terraform -chdir=terraform/environments/dev validate
```

기본 plan에서는 Dev EKS만 생성되어야 한다.

```bash
terraform -chdir=terraform/environments/dev plan \
  -out=/tmp/moment-dev-eks-cluster.tfplan \
  -var='dev_eks_public_access_cidrs=["<현재-public-ip>/32"]' \
  -no-color
```

Plan JSON에서 위험 변경과 범위 침범 리소스를 확인한다.

```bash
terraform -chdir=terraform/environments/dev show \
  -json /tmp/moment-dev-eks-cluster.tfplan \
  > /tmp/moment-dev-eks-cluster.plan.json
```

위험 변경 확인 기준은 다음과 같다.

```text
delete / replace 없음
aws_eks_node_group 없음
helm_release 없음
kubernetes workload 없음
aws_lb 계열 없음
```

## Apply 후 확인 명령

Apply 후에는 kubeconfig를 갱신한다.

```bash
aws eks update-kubeconfig \
  --region ap-northeast-3 \
  --name moment-dev-eks-cluster
```

Cluster와 Add-on 상태를 확인한다.

```bash
aws eks describe-cluster \
  --region ap-northeast-3 \
  --name moment-dev-eks-cluster \
  --query 'cluster.{name:name,status:status,version:version,endpoint:endpoint,oidc:identity.oidc.issuer}' \
  --output table

aws eks list-addons \
  --region ap-northeast-3 \
  --cluster-name moment-dev-eks-cluster \
  --output table
```

Kubernetes 접근 확인은 다음 명령으로 수행한다.

```bash
kubectl get nodes
kubectl get pods -A
```

단, M2-EKS-02 전에는 Managed NodeGroup이 없으므로 node 목록은 비어 있을 수 있다.

---

## Prod Managed NodeGroup 운영 기준 (M2-EKS-04)

> **2026-10-23 변경:** batch/ai 워크로드는 Karpenter NodePool(`on-demand-base`, `spot-burst`)로 옮긴다. 기존 batch/ai 노드그룹(`batch_on_demand`, `batch_spot`, `ai_spot`)은 `module.<env>_eks_legacy_nodegroups`로 옮겨 두었고, 이전이 끝나면 `enable_<env>_legacy_workload_nodegroups = false`로 제거한다. 최종적으로 `core_on_demand`(시스템 애드온)와 `ops_on_demand`(Karpenter 등 컨트롤러)만 남으며, 모든 노드그룹은 `max_pods = 40`(VPC CNI Prefix Delegation)이다. 현재 구성은 [karpenter.md](karpenter.md)를 기준으로 한다. 아래는 M2-EKS-04 당시 기준이다.

### 목적

Prod EKS Cluster 활성화 시 Worker Node가 필요하므로, 워크로드 특성에 따라 NodeGroup을 5종으로 분리하여 운영한다.

핵심 사용자 요청은 On-Demand에 배치하고, 재시도 가능한 Batch/AI 비동기 작업은 Spot으로 분리하여 비용을 최적화한다.

### 기본 활성화 정책

| 항목 | 기본값 | 설명 |
| --- | --- | --- |
| `enable_prod_nodegroups` | `false` | Prod NodeGroup은 별도 승인 후 명시적으로 활성화 |

기본 plan/apply에서는 Prod NodeGroup이 생성되지 않아야 한다.

Prod NodeGroup을 활성화하려면 다음 조건이 모두 true여야 한다.

```hcl
enable_prod_iam        = true
enable_prod_eks        = true
enable_prod_nodegroups = true
```

### NodeGroup 5종 구성

| NodeGroup | Capacity | instance_types | min | desired | max | 용도 |
| --- | --- | --- | --- | --- | --- | --- |
| core_on_demand | ON_DEMAND | t3.medium | 2 | 2 | 4 | Backend API, Auth, Payment, Reservation |
| batch_on_demand | ON_DEMAND | t3.medium | 0 | 1 | 2 | 긴 Batch, 중단 시 영향이 큰 정제 작업 |
| batch_spot | SPOT | t3.medium, t3.large | 0 | 0 | 3 | 짧고 재시도 가능한 Batch, SQS/DLQ 기반 |
| ai_spot | SPOT | t3.large, t3.xlarge | 0 | 1 | 3 | AI 비동기 처리, 검색 보조, 재시도 가능 작업 |
| ops_on_demand | ON_DEMAND | t3.medium | 1 | 1 | 2 | AWS Load Balancer Controller, ArgoCD, 운영 도구 |

### Node Label / Taint / Toleration 기준

#### Label

모든 NodeGroup에는 다음 두 label을 부여한다.

```text
workload: core | batch | ai | ops
capacity: on-demand | spot
```

Kubernetes Deployment에서 `nodeSelector` 또는 `nodeAffinity`로 워크로드를 원하는 NodeGroup에 배치한다.

#### Taint

| NodeGroup | Taint Key | Value | Effect |
| --- | --- | --- | --- |
| core_on_demand | 없음 | - | - |
| batch_on_demand | workload | batch | NO_SCHEDULE |
| batch_spot | spot | true | NO_SCHEDULE |
| ai_spot | spot | true | NO_SCHEDULE |
| ops_on_demand | 없음 | - | - |

`core_on_demand`와 `ops_on_demand`는 taint 없이 일반 스케줄링을 허용한다.

Spot NodeGroup과 batch_on_demand는 taint를 부여하여 의도하지 않은 워크로드 배치를 방지한다.

#### Toleration

Spot 또는 Batch NodeGroup에 배치할 Pod는 다음 toleration을 명시해야 한다.

batch_on_demand에 배치하려는 경우:

```yaml
tolerations:
  - key: "workload"
    value: "batch"
    effect: "NoSchedule"
    operator: "Equal"
```

batch_spot 또는 ai_spot에 배치하려는 경우:

```yaml
tolerations:
  - key: "spot"
    value: "true"
    effect: "NoSchedule"
    operator: "Equal"
```

toleration 없는 Pod는 core_on_demand 또는 ops_on_demand에만 스케줄링된다.

### Spot 중단 가능성과 재시도 정책

Spot Instance는 AWS가 용량 회수 시 2분 전 중단 알림 후 종료된다.

다음 워크로드만 Spot에 배치한다.

- 작업 단위가 짧고 중단 시 재시도 가능한 Batch
- SQS/DLQ 기반으로 재처리가 보장된 작업
- AI 비동기 처리 등 실패 허용 워크로드

다음 워크로드는 Spot에 배치하지 않는다.

- 사용자 요청을 직접 처리하는 API 서버
- 결제, 예약 등 트랜잭션 무결성이 필요한 서비스
- ArgoCD, ALB Controller 등 운영 도구

SQS 기반 Batch 작업의 재시도 정책은 다음과 같다.

| 항목 | 값 |
| --- | --- |
| max_receive_count | 3 |
| DLQ 보관 기간 | 14일 |
| Visibility Timeout | 300초 |

Spot 중단으로 작업이 중단되면 메시지가 visibility timeout 후 SQS로 복귀하여 자동 재처리된다.

### Terraform 구성 경로

```text
terraform/modules/eks-nodegroup
terraform/environments/prod/main.tf  # module "prod_eks_nodegroups"
```

### 제외 범위

| 항목 | 담당 이슈 |
| --- | --- |
| 실제 애플리케이션 Deployment 배치 변경 | M3 GitOps/Manifest |
| HPA / Cluster Autoscaler / Karpenter 튜닝 | Karpenter는 2026-10-23 도입([karpenter.md](karpenter.md)). Cluster Autoscaler는 쓰지 않음 |
| Prod 전체 apply | 별도 승인 후 수행 |
