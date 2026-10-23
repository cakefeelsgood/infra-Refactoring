# Monitoring 구조

## 개요
M4 Observability 구성을 위한 기본 구조.
kube-prometheus-stack (Prometheus + Grafana + Alertmanager) 기반으로 구성.

## 디렉토리 구조

monitoring/
├── prometheus/     # Prometheus 관련 설정
├── grafana/        # Grafana 대시보드 및 설정
├── alerting/       # Alertmanager 규칙
├── cloudwatch/     # CloudWatch 연동 설정
├── dashboards/     # Grafana 대시보드 JSON
└── runbooks/       # 장애 대응 Runbook

## 설계 결정

| 항목 | 결정 | 사유 |
|------|------|------|
| 설치 방식 | kube-prometheus-stack | Prometheus + Grafana + Alertmanager 통합 관리 |
| Grafana | 포함 | kube-prometheus-stack에 번들 |
| Alertmanager | 포함 | kube-prometheus-stack에 번들 |
| Loki/Promtail | 제외 | M4 범위 외, 비용 최적화 |
| Monitoring 접근 | port-forward 또는 OpenVPN | 일반 사용자 트래픽 경로와 분리 |
| observability/ 디렉토리 | 생성 안 함 | 기존 monitoring/ 구조 유지 |

## Dev 환경
- Prometheus retention: 7d
- Grafana persistence: 비활성
- namespace: monitoring

## Prod 환경
- Prometheus retention: 15d
- Grafana persistence: 활성 (10Gi)
- Prod EKS 비활성 상태 시 values만 문서화, 적용은 Prod EKS 활성화 시 진행

## GitOps 구조
- values: gitops/values/dev/monitoring-values.yaml
- ArgoCD App: gitops/argocd/dev/applications/monitoring-dev.yaml

## 민감정보 관리
- Grafana adminPassword는 Git에 평문 저장 안 함
- Secret으로 별도 관리

## Grafana Dashboard 관리 방식

- 방식: GitOps 관리 (ConfigMap)
- 대시보드 JSON을 ConfigMap으로 관리하고 Git에서 버전 관리
- 경로: monitoring/dashboards/
- Grafana sidecar를 통해 ConfigMap 자동 로드
