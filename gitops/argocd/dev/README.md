# Dev ArgoCD App of Apps

M3-ARGO-02는 Dev EKS에 설치된 Dev ArgoCD가 Dev Application만 관리하도록 App of Apps 구조를 구성한다.

## Scope

Dev ArgoCD는 다음만 관리한다.

- Dev Root Application
- Dev AppProject
- moment-dev namespace
- backend-api-dev Application
- ai-service-dev Application
- batch-job-dev Application

Prod Application은 이 경로에 두지 않는다.

Prod EKS, moment-prod namespace, Prod ArgoCD, Prod Application은 M3-ARGO-03에서 별도로 구성한다.

## Files

| File | Purpose |
| --- | --- |
| project.yaml | Dev 전용 AppProject |
| root-application.yaml | Dev App of Apps Root Application |
| namespaces/moment-dev.yaml | Dev application namespace |
| applications/backend-api-dev.yaml | Backend API Dev Application |
| applications/ai-service-dev.yaml | AI Service Dev Application |
| applications/batch-job-dev.yaml | Batch Job Dev Application |

## Root Application

| Field | Value |
| --- | --- |
| name | moment-dev-root |
| namespace | argocd |
| project | default |
| source path | gitops/argocd/dev |
| targetRevision | develop |
| destination namespace | argocd |

Root Application은 Dev AppProject, moment-dev Namespace, Dev child Application manifest를 함께 바라본다.

## Dev AppProject

| Field | Value |
| --- | --- |
| name | moment-dev |
| namespace | argocd |
| source repo | https://github.com/Team-msp-architect-2026/msp-team04-infra.git |
| destination server | https://kubernetes.default.svc |
| allowed namespaces | moment-dev, argocd |

moment-prod namespace와 Prod EKS destination은 허용하지 않는다.

## Dev Applications

| Application | Chart Path | valueFiles | Destination Namespace |
| --- | --- | --- | --- |
| backend-api-dev | gitops/charts/backend-api | ../../values/dev/backend-api-values.yaml | moment-dev |
| ai-service-dev | gitops/charts/ai-service | ../../values/dev/ai-service-values.yaml | moment-dev |
| batch-job-dev | gitops/charts/batch-job | ../../values/dev/batch-job-values.yaml | moment-dev |

## Sync Policy

Root Application은 Dev child Application manifest 생성을 위해 automated sync를 사용한다.

Child Application은 현재 단계에서 automated sync를 켜지 않는다.

이유는 M3-GITOPS-02에서 Helm Chart template이 완성되기 전까지 Runtime 리소스가 아직 없기 때문이다.

M3-GITOPS-02 이후 Backend API, AI Service, Batch Job chart template이 완성되면 Dev sync policy를 다시 검토한다.

## M3-CICD-03 Contract

M3-CICD-03은 다음 Dev values 파일의 `.image.tag`만 수정한다.

| Application | Values File | Field |
| --- | --- | --- |
| backend-api-dev | gitops/values/dev/backend-api-values.yaml | .image.tag |
| ai-service-dev | gitops/values/dev/ai-service-values.yaml | .image.tag |
| batch-job-dev | gitops/values/dev/batch-job-values.yaml | .image.tag |

ArgoCD Application은 위 values 파일을 참조하므로 image tag 변경을 감지할 수 있다.

## Current Limitation

현재 Helm Chart templates 디렉토리는 M3-GITOPS-02에서 실제 Deployment, Service, Ingress, Job, ServiceAccount template을 채우기 전까지 비어 있을 수 있다.

따라서 이번 이슈의 검증 기준은 다음이다.

- AppProject 생성 가능
- Root Application 생성 가능
- Child Application 생성 가능
- source repo / chart path / valueFiles 계약 확인
- Dev ArgoCD가 Prod Application을 만들지 않는지 확인

Runtime Pod Running, ALB Ingress 생성, ImagePull 검증은 M3-DEPLOY-01 / M3-DEPLOY-02에서 수행한다.
