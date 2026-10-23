# M4-VALID-A App / EKS / Metrics 관측성 검증

## 1. 목적

M4에서 구성한 Prometheus, Grafana, Cluster Dashboard, Application Metrics, Locust 부하 테스트 기반 관측성이 정상 동작하는지 검증한다.

운영자가 장애 발생 시 App / EKS / Metrics 관점에서 1차 확인할 수 있는 기준을 정리한다.

이번 검증은 Dev 환경을 중심으로 수행한다.

---

## 2. 검증 환경

- Cluster: moment-dev-eks-cluster
- Region: ap-northeast-3 (Osaka)
- Namespace: moment-dev (App), monitoring (Prometheus / Grafana)
- 검증 일시: 2026-06-09

---

## 3. Prometheus 검증 결과

### 3.1 Prometheus Pod 상태

```bash
kubectl get pods -n monitoring
```

결과:

| Pod | Ready | Status |
|-----|-------|--------|
| alertmanager-monitoring-dev-kube-promet-alertmanager-0 | 2/2 | Running |
| monitoring-dev-grafana-dc55bb84c-cfc6k | 3/3 | Running |
| monitoring-dev-kube-promet-operator-54484fc55d-b8nkl | 1/1 | Running |
| monitoring-dev-kube-state-metrics-5869c85d87-b6wd5 | 1/1 | Running |
| monitoring-dev-prometheus-node-exporter-* (4개) | 1/1 | Running |
| prometheus-monitoring-dev-kube-promet-prometheus-0 | 2/2 | Running |

모든 Pod Running 확인.

### 3.2 Prometheus Target 상태

Prometheus UI (`http://localhost:9090/targets`) 에서 확인.

- Unhealthy Target: 없음
- 주요 확인 Target:

| ServiceMonitor | 상태 |
|---|---|
| moment-ai-service-dev | 1/1 UP |
| moment-backend-api-dev | 1/1 UP |
| monitoring-dev-kube-state-metrics | 1/1 UP |
| monitoring-dev-prometheus-node-exporter | 4/4 UP |
| monitoring-dev-kube-promet-kubelet | 4/4 UP |
| monitoring-dev-kube-promet-apiserver | 2/2 UP |

### 3.3 kube-state-metrics 수집 확인

ServiceMonitor `monitoring-dev-kube-state-metrics` 1/1 UP 확인.

### 3.4 node-exporter 수집 확인

ServiceMonitor `monitoring-dev-prometheus-node-exporter` 4/4 UP 확인.
4개 노드 전체 수집 정상.

### 3.5 Application ServiceMonitor 동작 확인

#### Backend API

ServiceMonitor `moment-backend-api-dev` 1/1 UP 확인.

Prometheus Graph에서 다음 쿼리로 수집 확인:

```promql
http_server_requests_seconds_count{namespace="moment-dev"}
```

결과: `/health`, `/programs`, `/actuator/prometheus` 등 URI별 request count 수집 확인.

#### AI Service

ServiceMonitor `moment-ai-service-dev` 1/1 UP 확인.

Prometheus Graph에서 다음 쿼리로 수집 확인:

```promql
{job="ai-service"}
```

결과: `moment_ai_http_requests_total`, `moment_ai_http_request_duration_seconds_bucket`, `python_gc_objects_collected_total` 등 42개 메트릭 수집 확인.

#### Batch Job

Batch Job Pod는 CrashLoopBackOff 상태로 metrics endpoint 미노출.
Batch Job metrics 수집은 Batch Job 정상화 이후 재검증 필요.

---

## 4. Grafana 검증 결과

### 4.1 Grafana 접근

```bash
kubectl port-forward svc/monitoring-dev-grafana 3000:80 -n monitoring
```

브라우저: `http://localhost:3000`

### 4.2 Prometheus Datasource 연결 확인

- Datasource: Prometheus
- URL: `http://monitoring-dev-kube-promet-prometheus.monitoring:9090/`
- 상태: Successfully queried the Prometheus API ✅

### 4.3 Dashboard 확인

| Dashboard | 확인 결과 |
|---|---|
| Kubernetes / Compute Resources / Cluster | 정상 |
| Kubernetes / Compute Resources / Node (Pods) | 정상 |
| Kubernetes / Compute Resources / Pod | 정상 |
| Kubernetes / Compute Resources / Workload | 정상 |
| MoMent Dev Application / Business Overview | 정상 |

---

## 5. Application Metrics 검증 결과

### 5.1 Backend API

| 지표 | 확인 방법 | 결과 |
|---|---|---|
| request count | Grafana Backend Request Rate 패널 | 확인 |
| latency | Grafana Backend Avg Latency 패널 | 확인 |
| error rate | Grafana Backend 4xx/5xx Rate 패널 | 확인 |
| JVM memory | Grafana Backend JVM Heap Used 패널 | 확인 |
| CPU | Grafana Backend Process CPU Usage 패널 | 확인 |

### 5.2 AI Service

`moment_ai_http_requests_total` 등 커스텀 메트릭 수집 확인.
Prometheus Target UP, 42개 메트릭 수집 중.

### 5.3 Batch Job

CrashLoopBackOff 상태로 metrics 수집 불가.
Batch Job 정상화 후 재검증 필요.

---

## 6. 부하 테스트 검증 결과

M4-PERF-01에서 수행한 Locust Small Load Test 결과를 기반으로 검증한다.

### 6.1 테스트 조건

- 대상: Dev ALB
- Users: 20 / Spawn rate: 5 / Run time: 5m

### 6.2 테스트 결과

| 항목 | 결과 |
|---|---|
| Total Requests | 2,739 |
| Failures | 0 |
| Failure Rate | 0.00% |
| Avg Response Time | 47ms |
| Max Response Time | 408ms |
| Requests/sec | 9.16 |

### 6.3 부하 중 지표 변화

| 지표 | 변화 |
|---|---|
| Backend Request Rate | 부하 중 증가 확인 |
| Backend Avg Latency | 부하 중 변화 확인 |
| Backend 4xx/5xx Rate | 증가 없음 |
| Backend Process CPU | 부하 중 spike 확인 |
| Backend JVM Heap | 부하 중 증가 확인 |
| CloudWatch ALB RequestCount | 증가 확인 |
| CloudWatch 4XX Count | 증가 없음 |
| CloudWatch 5XX Count | 증가 없음 |
| HealthyHostCount | 정상 유지 |
| Pod restart count | 0 |
| Deployment available replicas | 1/1 유지 |

---

## 7. Prod 조건부 검증

### 7.1 Prod EKS 활성화 여부

검증 시점 기준 Prod EKS 비활성 상태.

```bash
kubectl get nodes --context arn:aws:eks:ap-northeast-3:611058323802:cluster/moment-prod-eks-cluster
# → 연결 불가 확인
```

### 7.2 Prod 검증 제외 사유

Prod EKS가 비활성 상태이므로 Prod Runtime 검증을 수행하지 않는다.
Prod는 프로젝트 마감 전 약 3일간 한시적으로 활성화되며, 활성화 시점에 동일 검증을 수행한다.

### 7.3 Prod 활성화 후 검증 절차

1. `aws eks update-kubeconfig --region ap-northeast-3 --name moment-prod-eks-cluster`
2. `kubectl get pods -n monitoring` → Prometheus / Grafana Running 확인
3. `kubectl port-forward svc/monitoring-prod-grafana 3000:80 -n monitoring`
4. Prometheus Target 상태 확인
5. Grafana Datasource 연결 확인
6. Backend API / AI Service metrics 수집 확인
7. CloudWatch ALB 지표 확인

---

## 8. 확인 절차 (장애 대응 Runbook)

### 8.1 Pod CPU 급증 시

1. `kubectl top pods -n moment-dev` → CPU 높은 Pod 확인
2. Grafana → Kubernetes / Compute Resources / Pod → 해당 Pod CPU 그래프 확인
3. `kubectl logs <pod> -n moment-dev` → 로그 확인
4. Grafana → MoMent Dev Application / Business Overview → request count / latency 확인
5. 비정상 요청 패턴 확인 후 필요 시 Pod restart 또는 HPA 검토

### 8.2 Pod Memory 급증 시

1. `kubectl top pods -n moment-dev` → Memory 높은 Pod 확인
2. Grafana → Kubernetes / Compute Resources / Pod → Memory Usage 그래프 확인
3. Grafana → MoMent Dev Application / Business Overview → Backend JVM Heap Used 확인
4. OOM 여부 확인: `kubectl describe pod <pod> -n moment-dev`
5. Memory limit 초과 시 Pod restart 발생 여부 확인
6. 지속 증가 시 Memory limit 조정 또는 코드 레벨 누수 검토

### 8.3 Request Latency 증가 시

1. Grafana → MoMent Dev Application / Business Overview → Backend Avg Latency 확인
2. CloudWatch → TargetResponseTime 확인
3. `kubectl top pods -n moment-dev` → CPU / Memory 이상 여부 확인
4. RDS / Redis 연결 상태 확인
5. `kubectl logs <backend-api-pod> -n moment-dev` → slow query 또는 connection timeout 로그 확인

### 8.4 HTTP 5xx 증가 시

1. CloudWatch → HTTPCode_Target_5XX_Count 확인
2. Grafana → Backend 4xx/5xx Rate 확인
3. `kubectl logs <backend-api-pod> -n moment-dev` → 에러 로그 확인
4. `kubectl get pods -n moment-dev` → CrashLoopBackOff 여부 확인
5. DB / Redis 연결 오류 여부 확인
6. ExternalSecret 정상 여부 확인: `kubectl get externalsecret -n moment-dev`

### 8.5 HPA 동작하지 않을 때

1. `kubectl get hpa -n moment-dev` → HPA 존재 여부 확인
2. `kubectl describe hpa <hpa-name> -n moment-dev` → 이벤트 확인
3. `kubectl top pods -n moment-dev` → CPU 사용률 확인
4. Metrics Server 동작 확인: `kubectl get deployment metrics-server -n kube-system`
5. HPA target CPU 기준과 실제 사용률 비교

### 8.6 Prometheus Target Down 시

1. `http://localhost:9090/targets` → Down된 Target 확인
2. `kubectl get servicemonitor -n monitoring` → ServiceMonitor 존재 확인
3. `kubectl get svc <service> -n moment-dev --show-labels` → Service label 확인
4. ServiceMonitor selector와 Service label 일치 여부 확인
5. `kubectl get endpoints <service> -n moment-dev` → Endpoint 존재 여부 확인
6. Pod의 metrics endpoint 정상 여부 확인: `curl http://<pod-ip>:<port>/actuator/prometheus`

---

## 9. 산출물

- Prometheus Target 검증 결과 (본 문서)
- Grafana Datasource 검증 결과 (본 문서)
- Cluster / Node / Pod Dashboard 캡처
- Application Dashboard 캡처
- Backend API metrics 검증 결과 (본 문서)
- AI Service metrics 확인 결과 (본 문서)
- Batch Job metrics 제외 사유 (본 문서)
- Locust 테스트 결과 (M4-PERF-01 참조)
- Prod 조건부 검증 결과 (본 문서)
- App / EKS / Metrics Runbook (본 문서)