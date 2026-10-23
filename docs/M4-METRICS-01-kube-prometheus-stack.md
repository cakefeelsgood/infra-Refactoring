# M4-METRICS-01 kube-prometheus-stack 설치 및 EKS 기본 메트릭 수집

## 설치 방식
- ArgoCD Application으로 관리
- chart: kube-prometheus-stack v61.3.0
- namespace: monitoring

## 설치된 컴포넌트
| 컴포넌트 | 상태 | 비고 |
|---------|------|------|
| Prometheus | Running | retention 7d |
| Grafana | Running | port-forward 접근 |
| Alertmanager | Running | 포함 |
| kube-state-metrics | Running | 포함 |
| node-exporter | Running | 노드 3개 |

## 접근 방법

### Prometheus
kubectl port-forward -n monitoring svc/monitoring-dev-kube-promet-prometheus 9090:9090
브라우저: http://localhost:9090

### Grafana
kubectl port-forward -n monitoring svc/monitoring-dev-grafana 3000:80
브라우저: http://localhost:3000 (admin / prom-operator)

## 수집 대상 (ServiceMonitor 14개)
- alertmanager
- apiserver
- coredns
- kube-controller-manager
- kube-etcd
- kube-proxy
- kube-scheduler
- kubelet
- node-exporter
- kube-state-metrics
- prometheus-operator
- prometheus

## Prod 환경
- Prod EKS 비활성 상태로 values / ArgoCD Application만 문서화
- 활성화 시 동일 구조로 적용
