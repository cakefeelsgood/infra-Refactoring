# M4 Monitoring GitOps 정합성 보완 기록

## 목적

M4-HEALTH-01 작업 전에 monitoring-dev / monitoring-prod GitOps 구성이 현재 develop 기준으로 재현 가능한지 점검하고, 발견된 정합성 문제를 보완한다.

이번 문서는 기존 팀원 M4 작업을 부정하기 위한 문서가 아니다.

팀원 작업 당시 runtime에서 Prometheus / Grafana가 정상 동작했을 가능성은 있다. 다만 현재 develop GitOps 원본 기준으로는 ArgoCD Application과 AppProject 권한, Helm values 구조 사이에 재현성 문제가 확인되었기 때문에 이를 코드로 보완한다.

## 발견된 문제

1. monitoring-dev Application이 moment-dev AppProject를 사용하고 있었다.
2. monitoring-prod Application이 moment-prod AppProject를 사용하고 있었다.
3. 기존 moment-dev / moment-prod AppProject에는 prometheus-community Helm chart repo가 sourceRepos에 없었다.
4. 기존 moment-dev / moment-prod AppProject에는 monitoring namespace가 destinations에 없었다.
5. 그 결과 ArgoCD에서 monitoring-dev / monitoring-prod가 InvalidSpecError 상태가 될 수 있었다.
6. Dev monitoring Application에는 source와 sources가 동시에 선언되어 있었다.
7. monitoring values가 kubePrometheusStack wrapper 아래에 있어 kube-prometheus-stack chart 직접 설치 방식에서는 values가 기대대로 반영되지 않을 수 있었다.

## 보완 방향

Application workload AppProject와 Monitoring AppProject를 분리한다.

기존 AppProject 역할:
- moment-dev: Dev Backend / AI / Batch 등 Application workload 관리
- moment-prod: Prod Backend / AI / Batch 등 Application workload 관리

신규 AppProject 역할:
- monitoring-dev: Dev kube-prometheus-stack 관리
- monitoring-prod: Prod kube-prometheus-stack 관리

## 변경 파일

- gitops/argocd/dev/monitoring-project.yaml
- gitops/argocd/prod/monitoring-project.yaml
- gitops/argocd/dev/applications/monitoring-dev.yaml
- gitops/argocd/prod/applications/monitoring-prod.yaml
- gitops/values/dev/monitoring-values.yaml
- gitops/values/prod/monitoring-values.yaml

## AppProject 분리 기준

monitoring-dev / monitoring-prod AppProject는 다음을 허용한다.

- source repo: msp-team04-infra GitHub repo
- source repo: prometheus-community Helm charts repo
- destination namespace: monitoring
- cluster-scoped resources:
  - Namespace
  - CustomResourceDefinition
  - MutatingWebhookConfiguration
  - ValidatingWebhookConfiguration
  - ClusterRole
  - ClusterRoleBinding
- namespaced resources:
  - ConfigMap
  - Secret
  - Service
  - ServiceAccount
  - Pod
  - Deployment
  - DaemonSet
  - StatefulSet
  - Job
  - Role
  - RoleBinding
  - Prometheus
  - Alertmanager
  - ServiceMonitor
  - PodMonitor
  - PrometheusRule

기존 moment-dev / moment-prod AppProject에는 monitoring용 cluster 권한을 섞지 않는다.

## Helm values 보완

kube-prometheus-stack chart를 직접 설치하므로 values는 chart top-level 구조로 작성한다.

사용 기준:
- prometheus
- grafana
- alertmanager
- loki
- promtail

제거한 잘못된 wrapper:
- kubePrometheusStack

## Dev values 기준

- Prometheus retention: 7d
- Grafana persistence: false
- Alertmanager enabled: true
- Loki enabled: false
- Promtail enabled: false

## Prod values 기준

- Prometheus retention: 15d
- Prometheus storage: 50Gi
- Grafana persistence: true
- Grafana storage: 10Gi
- Alertmanager enabled: true
- Loki enabled: false
- Promtail enabled: false

## 검증 결과

Static dry-run:
- gitops/argocd/dev/monitoring-project.yaml dry-run 성공
- gitops/argocd/prod/monitoring-project.yaml dry-run 성공
- gitops/argocd/dev/applications/monitoring-dev.yaml dry-run 성공
- gitops/argocd/prod/applications/monitoring-prod.yaml dry-run 성공

Values structure:
- kubePrometheusStack wrapper 없음
- Dev top-level values 확인: prometheus, grafana, alertmanager, loki, promtail
- Prod top-level values 확인: prometheus, grafana, alertmanager, loki, promtail

Rendered values:
- Dev retention: 7d 반영 확인
- Prod retention: 15d 반영 확인
- Prod Prometheus storage: 50Gi 반영 확인

Quality check:
- secret scan 이상 없음
- git diff --check 이상 없음

## Runtime 검증 기준

Runtime 리소스가 활성화된 상태에서는 다음을 확인해야 한다.

- monitoring-dev 또는 monitoring-prod Application Synced / Healthy
- monitoring namespace 생성
- Prometheus Pod Running
- Grafana Pod Running
- Alertmanager Pod Running
- kube-state-metrics Running
- node-exporter Running
- ServiceMonitor 생성
- Prometheus Target 정상
- Grafana datasource 정상
- Cluster / Node / Pod dashboard 조회 가능

## M4-HEALTH-01과의 관계

M4-HEALTH-01은 Backend API, AI Service, Batch Job의 Health Check / Probe / Uptime 관측 기준을 잡는 작업이다.

Health / Probe 상태를 Grafana / Alert와 연결하려면 monitoring stack이 GitOps 원본 기준으로 재현 가능해야 한다.

따라서 이번 보완은 M4-HEALTH-01 선행 정합성 보완으로 처리한다.
