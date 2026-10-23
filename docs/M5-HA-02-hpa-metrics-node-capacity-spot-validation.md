# [M5-HA-02] HPA / Metrics Server / Node Capacity / Spot 안정성 검증

## 1. 검증 목적

MoMent EKS 환경에서 HPA / Metrics Server / Node Capacity / Spot 배치 정책이 실무적으로 충돌 없이 동작하는지 검증한다.

이번 검증의 핵심은 다음과 같다.

- Metrics Server가 Kubernetes Metrics API를 정상 제공하는지 확인
- Backend API HPA가 CPU metric 기반으로 정상 계산되는지 확인
- HPA minReplicas / maxReplicas가 환경별 운영 기준과 맞는지 확인
- Backend API가 Spot NodeGroup이 아닌 Core On-Demand NodeGroup에 배치되는지 확인
- AI Service / Batch Job의 Spot 또는 전용 NodeGroup 배치 정책이 의도대로 분리되어 있는지 확인
- Cluster Autoscaler / Karpenter 도입 여부를 확인하고, 미도입 상태에서 HPA 상한이 현재 NodeGroup capacity 안에 있는지 확인
- Prod에서는 강제 부하 / 강제 scale-out / 장애 주입 없이 read-only 및 안전한 GitOps sync 기준으로 검증한다

## 2. 검증 범위

### 2.1 포함 범위

- Dev Metrics Server 상태 확인
- Dev Backend API HPA 상태 확인
- Dev Node label / capacity / taint / toleration 확인
- Prod Metrics Server GitOps 구성 추가 및 runtime 검증
- Prod Backend API HPA 활성화 및 runtime 검증
- Prod NodeGroup scalingConfig / capacityType / label / taint 확인
- Prod Backend API nodeSelector 및 실제 Pod 배치 확인
- Cluster Autoscaler / Karpenter 미구성 여부 확인
- HPA metric 계산 가능 여부 확인

### 2.2 제외 범위

- Prod 강제 부하 테스트
- Prod 강제 scale-out 유도
- Prod node drain / 장애 주입
- Locust 기반 대규모 부하 검증
- ALB / Edge / Route53 / ACM 전체 외부 트래픽 검증

대규모 부하와 용량 한계 검증은 M5-LOAD-01 범위로 분리한다.

## 3. 작업 브랜치 및 커밋

### 3.1 작업 브랜치

feature/hpa-metrics-node-spot-validation

### 3.2 머지 커밋

780dcee [#336] HPA / Metrics Server / Node Capacity / Spot 안정성 검증

### 3.3 주요 변경 파일

- gitops/argocd/prod/metrics-server-project.yaml
- gitops/argocd/prod/applications/metrics-server-prod.yaml
- gitops/values/prod/backend-api-values.yaml

## 4. 구현 내용

### 4.1 Prod Metrics Server GitOps 추가

Prod 환경에 metrics-server-prod AppProject와 Application을 추가했다.

구성 기준은 다음과 같다.

- chart: metrics-server
- targetRevision: 3.13.0
- namespace: kube-system
- releaseName: metrics-server
- replicas: 1
- podDisruptionBudget.enabled: true
- podDisruptionBudget.minAvailable: 1
- resources.requests.cpu: 100m
- resources.requests.memory: 200Mi
- nodeSelector.workload: ops
- nodeSelector.capacity: on-demand
- toleration: workload=ops:NoSchedule

Metrics Server는 운영 도구 성격이므로 ops/on-demand NodeGroup에 배치되도록 구성했다.

### 4.2 Prod Backend API HPA 활성화

Prod Backend API values에서 autoscaling을 활성화했다.

최종 기준은 다음과 같다.

- autoscaling.enabled: true
- minReplicas: 2
- maxReplicas: 4
- targetCPUUtilizationPercentage: 70
- targetMemoryUtilizationPercentage: null
- scaleUp policy: Pods 1 / 60s
- scaleDown stabilizationWindowSeconds: 300
- scaleDown policy: Percent 50 / 60s

중요하게, Dev 기준 minReplicas=1 / maxReplicas=2를 그대로 복사하지 않고 Prod 기존 운영 후보 기준인 minReplicas=2 / maxReplicas=4를 유지했다.

### 4.3 Backend API 배치 정책 유지

Prod Backend API는 다음 NodeGroup 배치 정책을 유지한다.

- nodeSelector.workload: core
- nodeSelector.capacity: on-demand
- tolerations: 없음

따라서 Backend API는 Spot NodeGroup에 배치되지 않는다.

## 5. Static Validation 결과

### 5.1 Terraform validate

Dev / Prod Terraform validate 모두 성공했다.

결과:

- terraform -chdir=terraform/environments/dev validate: Success
- terraform -chdir=terraform/environments/prod validate: Success

### 5.2 Helm template 검증

Prod Backend API Helm 렌더링 결과 HorizontalPodAutoscaler가 정상 생성되는 것을 확인했다.

렌더링 확인 항목:

- kind: Deployment
- resources.requests 존재
- nodeSelector.capacity: on-demand
- nodeSelector.workload: core
- kind: HorizontalPodAutoscaler
- minReplicas: 2
- maxReplicas: 4
- averageUtilization: 70

## 6. AWS EKS / NodeGroup 검증

### 6.1 Dev NodeGroup

Dev NodeGroup 상태:

- moment-dev-ai-spot-ng
  - capacityType: SPOT
  - desiredSize: 0
  - minSize: 0
  - maxSize: 2
  - labels: workload=ai, capacity=spot
  - taints: workload=ai:NoSchedule, capacity=spot:NoSchedule

- moment-dev-batch-spot-ng
  - capacityType: SPOT
  - desiredSize: 1
  - minSize: 0
  - maxSize: 2
  - labels: workload=batch, capacity=spot
  - taints: workload=batch:NoSchedule, capacity=spot:NoSchedule

- moment-dev-core-on-demand-ng
  - capacityType: ON_DEMAND
  - desiredSize: 2
  - minSize: 1
  - maxSize: 2
  - labels: workload=core, capacity=on-demand
  - taints: 없음

- moment-dev-ops-on-demand-ng
  - capacityType: ON_DEMAND
  - desiredSize: 1
  - minSize: 1
  - maxSize: 2
  - labels: workload=ops, capacity=on-demand
  - taints: workload=ops:NoSchedule

### 6.2 Prod NodeGroup

Prod NodeGroup 상태:

- moment-prod-ai-spot-ng
  - capacityType: SPOT
  - desiredSize: 1
  - minSize: 0
  - maxSize: 3
  - instanceTypes: t3.large, t3.xlarge
  - labels: workload=ai, capacity=spot
  - taints: workload=ai:NoSchedule, capacity=spot:NoSchedule

- moment-prod-batch-on-demand-ng
  - capacityType: ON_DEMAND
  - desiredSize: 1
  - minSize: 0
  - maxSize: 2
  - labels: workload=batch, capacity=on-demand
  - taints: workload=batch:NoSchedule

- moment-prod-batch-spot-ng
  - capacityType: SPOT
  - desiredSize: 0
  - minSize: 0
  - maxSize: 3
  - instanceTypes: t3.medium, t3.large
  - labels: workload=batch, capacity=spot
  - taints: workload=batch:NoSchedule, capacity=spot:NoSchedule

- moment-prod-core-on-demand-ng
  - capacityType: ON_DEMAND
  - desiredSize: 2
  - minSize: 2
  - maxSize: 4
  - labels: workload=core, capacity=on-demand
  - taints: 없음

- moment-prod-ops-on-demand-ng
  - capacityType: ON_DEMAND
  - desiredSize: 2
  - minSize: 2
  - maxSize: 3
  - labels: workload=ops, capacity=on-demand
  - taints: workload=ops:NoSchedule

## 7. Dev Runtime 검증 결과

### 7.1 Dev Metrics Server

Dev Metrics Server 상태:

- v1beta1.metrics.k8s.io Available=True
- metrics-server Deployment 1/1 Ready
- kubectl top nodes 성공
- kubectl top pods -A 성공

### 7.2 Dev Backend API HPA

Dev Backend API HPA 상태:

- namespace: moment-dev
- name: backend-api
- reference: Deployment/backend-api
- target: cpu 70%
- minReplicas: 1
- maxReplicas: 2
- replicas: 1
- ScalingActive=True
- ValidMetricFound

Dev HPA는 Metrics Server를 통해 CPU metric을 정상 계산했다.

### 7.3 Dev 배치 정책

Dev Backend API:

- nodeSelector.workload: core
- nodeSelector.capacity: on-demand
- resources.requests 존재
- Spot node에 배치되지 않음

Dev Batch Job:

- nodeSelector.workload: batch
- nodeSelector.capacity: spot
- tolerations:
  - workload=batch:NoSchedule
  - capacity=spot:NoSchedule

Dev AI Service:

- nodeSelector.workload: core
- nodeSelector.capacity: on-demand

## 8. Prod Runtime 검증 결과

### 8.1 Prod Metrics Server

Prod Metrics Server는 GitOps 반영 후 정상 배포되었다.

확인 결과:

- metrics-server-prod: Synced / Healthy
- kube-system metrics-server Deployment: 1/1 Ready
- metrics-server Pod: 1/1 Running
- v1beta1.metrics.k8s.io: Available=True
- kubectl top nodes: 성공
- kubectl top pods -A: 성공

### 8.2 Prod Backend API HPA

Prod Backend API HPA는 GitOps sync 후 정상 생성되었다.

확인 결과:

- namespace: moment-prod
- name: backend-api
- reference: Deployment/backend-api
- target: cpu 70%
- current metric: cpu 0%
- minReplicas: 2
- maxReplicas: 4
- replicas: 2
- Deployment pods: 2 current / 2 desired
- AbleToScale=True
- ScalingActive=True
- Reason: ValidMetricFound
- ScalingLimited=True
- Reason: TooFewReplicas

ScalingLimited=True / TooFewReplicas는 장애가 아니다.
현재 CPU 사용률 기준으로는 더 줄일 수 있지만, minReplicas=2 하한 때문에 2개를 유지한다는 의미다.
이는 Prod 최소 가용성 기준이 정상 적용되고 있다는 증거다.

### 8.3 Prod HPA rescale 이벤트

HPA 생성 직후 다음 이벤트가 발생했다.

- Reason: SuccessfulRescale
- Message: New size: 2; reason: Current number of replicas below Spec.MinReplicas

이는 HPA가 minReplicas=2 기준을 적용하여 Backend API replicas를 2로 맞춘 정상 이벤트다.

### 8.4 Prod Backend API 배치 정책

Prod Backend API Deployment 상태:

- replicas: 2
- strategy.maxSurge: 1
- strategy.maxUnavailable: 0
- resources.requests 존재
- resources.limits 존재
- nodeSelector.capacity: on-demand
- nodeSelector.workload: core

Prod Backend API Pod 상태:

- backend-api-5788488b98-ctm77: Running
- backend-api-5788488b98-t47cs: Running

Pod는 core/on-demand Node에 배치되었다.

## 9. Cluster Autoscaler / Karpenter 확인

현재 Dev / Prod 환경에서 Cluster Autoscaler 또는 Karpenter workload / CRD는 확인되지 않았다.

판정:

- Cluster Autoscaler: 미구성
- Karpenter: 미구성
- HPA는 Pod replica만 조절한다
- Node 자동 증설은 현재 범위에 포함되지 않는다
- 따라서 HPA maxReplicas는 기존 NodeGroup capacity 안에서 안전하게 설정해야 한다

Prod Backend API HPA maxReplicas=4는 core_on_demand NodeGroup maxSize=4 기준과 충돌하지 않는 범위로 판단한다.

## 10. Prod backend-api-prod ArgoCD Health Progressing 분리

Prod backend-api-prod Application은 Sync 관점에서는 정상이다.

확인 결과:

- backend-api-prod sync: Synced
- operationPhase: Succeeded
- operationMessage: successfully synced (all tasks run)
- Deployment: Synced
- HorizontalPodAutoscaler: Synced
- Service: Synced
- ServiceAccount: Synced
- ConfigMap: Synced
- PodDisruptionBudget: Synced
- Ingress: Synced

하지만 Health는 Progressing으로 표시되었다.

원인 확인 결과:

- Deployment rollout: successfully rolled out
- Deployment READY: 2/2
- Deployment Available=True
- Service endpoints 존재
- HPA 정상
- Metrics API 정상
- Ingress ADDRESS 비어 있음
- Ingress event:
  - FailedBuildModel
  - couldn't auto-discover subnets
  - unable to resolve at least one subnet

따라서 backend-api-prod Health Progressing은 HPA / Metrics Server 문제가 아니다.
ALB Ingress Controller가 subnet auto-discovery에 실패하여 ALB ADDRESS가 할당되지 않은 별도 Edge / ALB / subnet tagging 이슈다.

이 항목은 M5-HA-02 완료를 막는 핵심 실패로 보지 않고, 후속 ALB / Ingress / subnet tagging 이슈로 분리한다.

## 11. 최종 판정

### 11.1 충족 항목

- Dev Metrics Server 정상
- Dev Backend API HPA 정상
- Prod Metrics Server GitOps 구성 추가
- Prod Metrics Server runtime 정상
- Prod Metrics API Available=True
- Prod kubectl top nodes 성공
- Prod kubectl top pods -A 성공
- Prod Backend API HPA 생성
- Prod HPA CPU metric 계산 정상
- Prod HPA minReplicas=2 / maxReplicas=4 확인
- Prod HPA replicas=2 유지 확인
- Prod Backend API core/on-demand 배치 유지
- Backend API Spot 오배치 없음
- Cluster Autoscaler / Karpenter 미구성 확인
- Prod 강제 부하 / 장애 주입 미수행
- ALB Progressing 원인 분리

### 11.2 미수행 항목

- Prod 강제 부하로 HPA scale-out 유도
- Prod node drain
- Prod Spot interruption simulation
- Locust 기반 대규모 부하 테스트

미수행 사유:

- Prod 안정성 보호
- 이번 이슈는 HPA / Metrics Server / Node Capacity / Spot 배치 정합성 검증이 핵심
- 대규모 부하 검증은 M5-LOAD-01에서 별도 수행

### 11.3 최종 결론

[M5-HA-02] HPA / Metrics Server / Node Capacity / Spot 안정성 검증은 충족한다.

Dev와 Prod 모두 Metrics API 및 HPA 검증 경로를 확인했다.
Prod에는 누락되어 있던 Metrics Server와 Backend API HPA를 GitOps 방식으로 보완했고, runtime에서 Metrics API와 HPA가 정상 동작함을 확인했다.
Backend API는 core/on-demand NodeGroup에 배치되어 Spot NodeGroup 오배치가 발생하지 않았다.
현재 Cluster Autoscaler / Karpenter는 미구성 상태이므로 HPA는 Pod replica만 조절하며 Node 자동 증설은 수행하지 않는다.
backend-api-prod ArgoCD Health Progressing은 Ingress ALB subnet auto-discovery 실패로 인한 별도 이슈이며, HPA / Metrics Server 검증 결과와 분리한다.

## 12. 후속 이슈 후보

### 12.1 ALB / Ingress subnet auto-discovery 보완

Prod backend-api Ingress에서 ALB ADDRESS가 비어 있고, AWS Load Balancer Controller가 subnet auto-discovery에 실패한다.

후속으로 다음 항목을 확인해야 한다.

- Prod public/private subnet tag
- kubernetes.io/cluster/moment-prod-eks-cluster tag
- kubernetes.io/role/elb 또는 kubernetes.io/role/internal-elb tag
- ALB Controller subnet discovery 조건
- Ingress scheme internet-facing 기준 subnet 선택
- Prod ALB 생성 및 ADDRESS 할당 여부

### 12.2 Cluster Autoscaler 또는 Karpenter 도입 검토

현재 HPA는 Pod replica만 조절하며 Node 자동 증설은 없다.
향후 부하 테스트에서 Node capacity 한계가 확인되면 Cluster Autoscaler 또는 Karpenter 도입을 검토한다.

### 12.3 M5-LOAD-01 연계

Locust 기반 단계별 부하 테스트에서 다음을 확인한다.

- Backend API HPA scale-out
- Pod Pending 발생 여부
- Node capacity 한계
- ALB target health
- RDS / Redis / OpenSearch 병목 여부
- Grafana / CloudWatch 관측 지표
