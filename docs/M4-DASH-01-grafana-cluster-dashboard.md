# M4-DASH-01 Grafana Cluster / Node / Pod 대시보드 구성

## 개요
kube-prometheus-stack 설치 시 기본 제공되는 Grafana 대시보드를 기반으로 Cluster / Node / Pod 관점의 대시보드 구성 완료.

## Grafana 접근 방법
port-forward 방식 사용 (외부 공개 없음)

kubectl port-forward -n monitoring svc/monitoring-dev-grafana 3000:80

브라우저: http://localhost:3000 (admin / prom-operator)

## Prometheus Datasource
- 연결 상태: 정상 (default)
- URL: http://monitoring-dev-kube-promet-prometheus:9090

## 구성된 대시보드

| 대시보드 | 용도 |
|---------|------|
| Kubernetes / Compute Resources / Cluster | Cluster 전체 CPU/Memory 사용률, Namespace별 리소스 |
| Node Exporter / Nodes | Node CPU, Memory, Disk, Network |
| Kubernetes / Compute Resources / Namespace (Pods) | Namespace별 Pod CPU/Memory |
| Kubernetes / Compute Resources / Pod | Pod 단위 CPU/Memory 상세 |
| Kubernetes / Compute Resources / Workload | Workload 단위 리소스 사용량 |

## Dashboard 관리 방식
- kube-prometheus-stack 기본 제공 대시보드 사용
- ConfigMap 기반 GitOps 관리 (sidecar 자동 로드)
- 커스텀 대시보드 추가 시 monitoring/dashboards/ 하위에 JSON 저장

## NodeGroup 관측
- On-Demand / Spot NodeGroup label 미설정으로 NodeGroup별 구분 패널 없음
- kube_node_info 메트릭으로 노드 정보 확인 가능

## Prod 환경
- Prod EKS 비활성 상태로 동일 구조 적용 보류
- 활성화 시 동일 values로 자동 구성됨

## Prometheus 메트릭 확인 결과 (Grafana Explore)

| 메트릭 | 쿼리 | 결과 |
|--------|------|------|
| Pod restart count | kube_pod_container_status_restarts_total | ✅ 51개 시리즈 |
| Pending Pod | kube_pod_status_phase{phase="Pending"} | ✅ 전체 0 (정상) |
| CrashLoopBackOff | kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"} | ✅ argocd-applicationset-controller 1개 감지 |
| HPA replica | kube_horizontalpodautoscaler_status_current_replicas | ⬜ HPA 미배포로 No data |
| Namespace CPU request | kube_pod_container_resource_requests{resource="cpu"} | ✅ 32개 시리즈 |

## Wiki 업데이트 필요
- 대상: https://github.com/Team-msp-architect-2026/msp-team04-wiki/wiki/Monitoring-%EA%B5%AC%EC%B6%95
- 내용: Grafana Cluster / Node / Pod 대시보드 구성 내용 추가
