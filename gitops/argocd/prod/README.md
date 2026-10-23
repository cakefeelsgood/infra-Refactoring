# Prod ArgoCD Path Contract

M3-ARGO-03에서 Prod ArgoCD와 Prod Application manifest를 이 경로 아래에 작성한다.

Prod ArgoCD는 Prod EKS Cluster 내부에 별도로 설치되며, Prod Application만 관리한다.
Dev ArgoCD가 Prod Application 또는 moment-prod namespace를 관리하지 않는다.

## 구성 파일

| 파일 | 역할 |
| --- | --- |
| project.yaml | Prod 전용 AppProject |
| namespaces/moment-prod.yaml | Prod workload namespace |
| root-application.yaml | Prod App of Apps Root Application |
| applications/backend-api-prod.yaml | Backend API Prod Application |
| applications/ai-service-prod.yaml | AI Service Prod Application |
| applications/batch-job-prod.yaml | Batch Job Prod Application |

## Root Application

| 항목 | 값 |
| --- | --- |
| name | moment-prod-root |
| namespace | argocd |
| source repo | https://github.com/Team-msp-architect-2026/msp-team04-infra.git |
| targetRevision | develop |
| source path | gitops/argocd/prod |
| destination namespace | argocd |

Root Application은 Prod AppProject, moment-prod namespace, Prod child Application CR을 등록하기 위한 App of Apps 진입점이다.

## Prod Application 계약

| Application | Chart path | Values file | Destination namespace | Sync policy |
| --- | --- | --- | --- | --- |
| backend-api-prod | gitops/charts/backend-api | ../../values/prod/backend-api-values.yaml | moment-prod | manual |
| ai-service-prod | gitops/charts/ai-service | ../../values/prod/ai-service-values.yaml | moment-prod | manual |
| batch-job-prod | gitops/charts/batch-job | ../../values/prod/batch-job-values.yaml | moment-prod | manual |

Prod child Application에는 automated sync를 설정하지 않는다.
Prod workload 실제 sync와 smoke test는 승인 후 M3-PROMOTE-01 흐름에서 수행한다.

## Prod / Dev 경계

- 이 경로에는 Dev Application을 두지 않는다.
- Prod ArgoCD는 moment-prod namespace만 workload destination으로 허용한다.
- Dev ArgoCD는 moment-prod namespace와 Prod Application을 관리하지 않는다.
- Prod Application은 Dev처럼 자동 동기화하지 않고, diff 확인과 승인 이후 manual sync하는 방식을 기본으로 한다.

## Bootstrap 전제

현재 비용 절감을 위해 Dev runtime은 내려간 상태이며, Prod EKS도 항상 존재한다고 가정하지 않는다.

Prod bootstrap은 Prod EKS Cluster가 존재하고 kubectl 접근이 가능한 시점에만 수행한다.

명령:

CONFIRM_PROD=prod make argocd-prod-bootstrap

검증:

make argocd-prod-verify

## 제외 범위

- 이 경로는 Prod Application 구성을 정의한다.
- Prod EKS 생성은 Terraform 승인 흐름에 따른다.
- Prod workload 실제 sync는 이 파일 생성만으로 수행되지 않는다.
- Prod full app sync / smoke test는 M3-PROMOTE-01에서 진행한다.
- Secret 값은 GitOps repository에 평문으로 저장하지 않는다.
