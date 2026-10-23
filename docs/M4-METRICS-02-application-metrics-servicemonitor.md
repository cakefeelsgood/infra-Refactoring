# M4-METRICS-02 Application Metrics / ServiceMonitor 수집 기준 구성

## 1. 목적

Backend API, AI Service, Batch Worker의 Application Metrics 수집 가능 여부를 실제 코드, Helm chart, Kubernetes Service, Runtime endpoint 기준으로 확인하고 Prometheus ServiceMonitor 또는 PodMonitor 적용 기준을 정의한다.

이번 이슈에서는 존재하지 않는 metrics endpoint를 가정하여 가짜 ServiceMonitor 또는 깨지는 Prometheus Target을 만들지 않는다.

## 2. 확인 대상

- Backend API
- AI Service
- Batch Worker
- kube-prometheus-stack Prometheus selector
- ArgoCD AppProject 권한 경계
- Dev / Prod Runtime endpoint 응답

## 3. Prometheus 수집 selector 기준

kube-prometheus-stack 렌더링 결과 Prometheus는 ServiceMonitor와 PodMonitor를 다음 기준으로 선택한다.

- serviceMonitorSelector.matchLabels.release = monitoring-dev 또는 monitoring-prod
- podMonitorSelector.matchLabels.release = monitoring-dev 또는 monitoring-prod
- serviceMonitorNamespaceSelector = {}
- podMonitorNamespaceSelector = {}

따라서 Application Metrics용 ServiceMonitor 또는 PodMonitor를 생성할 경우 release 라벨이 반드시 필요하다.

## 4. ArgoCD AppProject 기준

현재 GitOps 구조는 Application workload와 Monitoring stack의 AppProject를 분리한다.

- moment-dev / moment-prod
  - Backend API, AI Service, Batch Worker 등 application workload 관리
  - ServiceMonitor / PodMonitor 권한 없음
- monitoring-dev / monitoring-prod
  - kube-prometheus-stack 및 monitoring resource 관리
  - ServiceMonitor / PodMonitor / PrometheusRule 권한 있음

따라서 실무적으로 Application Metrics ServiceMonitor는 workload chart에 직접 섞기보다 monitoring AppProject가 소유하는 중앙 관리 방식이 적합하다.

## 5. Backend API 확인 결과

### 코드 기준

Backend API 코드 확인 결과 다음 항목이 기존에는 존재하지 않았다.

- spring-boot-starter-actuator 의존성
- micrometer-registry-prometheus 의존성
- management.endpoints.web.exposure.include 설정
- management.endpoint.prometheus.enabled 설정
- SecurityConfig의 /actuator/prometheus permitAll 설정

### Runtime 기준

Dev / Prod Backend API에 대해 /actuator/prometheus를 확인한 결과 401 UNAUTHORIZED가 반환되었다.

이는 Prometheus가 인증 없이 scrape 가능한 endpoint 상태가 아님을 의미한다.

### 판정

현재 #329 기준에서는 Backend API ServiceMonitor를 생성하지 않는다.

후속 이슈에서 Backend API에 Actuator / Micrometer / Prometheus endpoint를 실제 구현하고 /actuator/prometheus HTTP 200을 확인한 뒤 ServiceMonitor를 적용한다.

## 6. AI Service 확인 결과

### 코드 기준

AI Service 코드 확인 결과 다음 항목이 기존에는 존재하지 않았다.

- prometheus-client 또는 prometheus-fastapi-instrumentator 의존성
- /metrics route
- request count / latency / error metrics middleware

### Runtime 기준

Dev / Prod AI Service에 대해 /metrics를 확인한 결과 404 Not Found가 반환되었다.

### 판정

현재 #329 기준에서는 AI Service ServiceMonitor를 생성하지 않는다.

후속 이슈에서 AI Service에 /metrics endpoint를 실제 구현하고 HTTP 200을 확인한 뒤 ServiceMonitor를 적용한다.

## 7. Batch Worker 확인 결과

### Helm / Runtime 기준

Dev / Prod Batch는 현재 CronJob이 아니라 Worker Deployment 모드로 동작한다.

확인 결과:

- Deployment batch-job 존재
- CronJob batch-job 없음
- Service batch-job 없음
- Pod Ready 1/1
- Restart 0

### 판정

현재 Batch Worker는 HTTP metrics endpoint와 Kubernetes Service가 없으므로 ServiceMonitor 또는 PodMonitor를 생성하지 않는다.

Batch Worker는 우선 다음 지표로 관측한다.

- kube-state-metrics 기반 Deployment available replicas
- kube-state-metrics 기반 Pod restart count
- kube-state-metrics 기반 Pod waiting reason
- SQS CloudWatch ApproximateNumberOfMessagesVisible
- SQS CloudWatch DLQ visible messages

후속 이슈에서 Batch Worker custom application metrics가 필요하면 별도 HTTP metrics endpoint 또는 Spring Actuator 기반 endpoint를 설계한다.

## 8. 최종 기준

현재 #329에서 ServiceMonitor / PodMonitor를 만들지 않는다.

이유:

- Backend /actuator/prometheus가 scrape 가능하지 않음
- AI /metrics가 존재하지 않음
- Batch Worker는 Service/HTTP metrics endpoint가 없음
- 없는 endpoint에 ServiceMonitor를 만들면 Prometheus Target 장애가 발생함

후속 구현 후 ServiceMonitor를 적용할 때의 기준:

- metadata.labels.release = monitoring-dev 또는 monitoring-prod
- namespaceSelector.matchNames = moment-dev 또는 moment-prod
- selector.matchLabels는 실제 Service label과 일치
- endpoints.port는 Service port name 사용
- Backend path = /actuator/prometheus
- AI path = /metrics
- Batch는 endpoint 구현 전까지 제외

## 9. 후속 이슈

제안 후속 이슈:

[M4-METRICS-03] Backend·AI Application Metrics Endpoint 구현 및 ServiceMonitor 연동

범위:

- Backend Actuator / Micrometer / Prometheus endpoint 구현
- Backend SecurityConfig에서 /actuator/prometheus scrape 허용
- AI Service prometheus-client 기반 /metrics endpoint 구현
- Dev / Prod 이미지 빌드 및 배포
- monitoring AppProject 소유 ServiceMonitor 추가
- Prometheus Targets에서 Backend / AI scrape 상태 확인
- Batch Worker는 현재 ServiceMonitor 대상에서 제외하고 별도 custom metrics 후보로 문서화

