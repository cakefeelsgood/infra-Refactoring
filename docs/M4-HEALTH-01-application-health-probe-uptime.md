# M4-HEALTH-01 Application Health Check / Probe / Uptime 관측 기준

## 개요

이 문서는 MoMent Backend API, AI Service, Batch Job의 Health Check, Kubernetes Probe, Workload 상태 관측 기준을 정리한다.

이번 이슈의 목적은 Grafana Dashboard 완성이나 Slack Alert 구성이 아니다.
M4-DASH-02와 M4-ALERT-01에서 사용할 Health Panel 후보와 Alert Rule 후보를 정의하기 위한 선행 기준을 확정한다.

M4에서는 Loki / Promtail 기반 중앙 로그 수집은 제외하고 Metrics / Health / Probe 중심으로 관측한다.

## 대상 Workload

- backend-api
- ai-service
- batch-job

## Backend API Health 기준

Backend API는 Kubernetes readinessProbe / livenessProbe와 ALB Target Group Health Check 기준을 분리한다.

현재 Backend API Kubernetes Probe 기준:

- readinessProbe: tcpSocket 8080
- livenessProbe: tcpSocket 8080

현재 Backend API ALB Health Check 기준:

- path: /health
- success codes: 200,401

## Backend API에서 TCP Probe를 사용하는 이유

Backend API의 /health endpoint는 Spring Security 정책 또는 애플리케이션 설정에 따라 401을 반환할 수 있다.

ALB Target Group Health Check는 success-codes 200,401 기준으로 처리할 수 있지만, Kubernetes HTTP probe가 401을 받으면 Pod를 비정상으로 판단할 수 있다.

따라서 Backend API는 다음 기준으로 분리한다.

- Kubernetes Probe: 컨테이너 프로세스가 8080 포트에서 정상 listen 중인지 확인
- ALB Health Check: 외부 트래픽 진입 경로에서 /health 응답 상태 확인

이 기준은 Pod 생존성과 외부 트래픽 라우팅 상태를 혼동하지 않기 위한 것이다.

## Backend API Probe 설정

Dev / Prod 모두 동일 계열의 TCP readinessProbe / livenessProbe를 사용한다.

readiness 기준:

- port: 8080
- initialDelaySeconds: 30
- periodSeconds: 5
- timeoutSeconds: 2
- failureThreshold: 30
- successThreshold: 1

liveness 기준:

- port: 8080
- initialDelaySeconds: 180
- periodSeconds: 15
- timeoutSeconds: 2
- failureThreshold: 5
- successThreshold: 1

startupProbe는 현재 필수로 적용하지 않는다.
다만 Helm chart에는 startupProbe 확장 지점을 열어두어 추후 부팅 시간이 길어지는 경우 values에서 추가할 수 있도록 한다.

## AI Service Health 기준

AI Service는 /health endpoint를 기준으로 Kubernetes HTTP readinessProbe / livenessProbe를 사용한다.

현재 AI Service Probe 기준:

readiness:

- path: /health
- port: 8000
- initialDelaySeconds: 20
- periodSeconds: 10
- timeoutSeconds: 2
- failureThreshold: 6
- successThreshold: 1

liveness:

- path: /health
- port: 8000
- initialDelaySeconds: 40
- periodSeconds: 15
- timeoutSeconds: 2
- failureThreshold: 5
- successThreshold: 1

AI Service의 Probe 값은 chart template에 hardcoded하지 않고 values.yaml 기준으로 관리한다.

startupProbe는 현재 필수로 적용하지 않는다.
다만 Helm chart에는 startupProbe 확장 지점을 열어두어 모델 로딩 또는 외부 의존성 초기화가 길어지는 경우 values에서 추가할 수 있도록 한다.

## Batch Job 실행 모드 기준

현재 Dev / Prod Batch Job은 CronJob이 아니라 Worker Deployment 모드다.

현재 values 기준:

- mode: worker
- kind: Deployment
- SPRING_BATCH_JOB_ENABLED: false
- BATCH_SQS_CONSUMER_ENABLED: true

따라서 이번 이슈에서 Batch Job을 CronJob / Job 성공, 실패, 완료 시간 중심으로 단정하지 않는다.

현재 Batch Job은 SQS polling worker로 동작하므로 다음 기준으로 관측한다.

- Deployment Available
- Pod Ready
- Pod restart count
- Container waiting reason
- BATCH_SQS_CONSUMER_ENABLED 설정값
- SQS queue depth 후보
- DLQ message count 후보

## Batch Worker에 HTTP Probe를 억지로 추가하지 않는 이유

현재 Batch Worker는 Spring Batch one-shot Job이 아니라 SQS polling worker Deployment로 동작한다.

HTTP 서버로 health endpoint를 제공하는 구조가 명확히 확인되지 않은 상태에서 /health probe를 추가하면 오히려 정상 worker를 비정상으로 판단할 수 있다.

따라서 이번 이슈에서는 Batch Worker에 임시 HTTP Probe를 추가하지 않는다.

Batch Worker 관측은 다음 계층으로 나눈다.

- Kubernetes: Deployment Available, Pod Ready, Restart Count
- Application Config: BATCH_SQS_CONSUMER_ENABLED
- AWS Managed Metrics: SQS ApproximateNumberOfMessagesVisible, DLQ message count
- 후속 Application Metrics: 처리 성공/실패/소요시간 커스텀 메트릭 후보

## Grafana Health Panel 후보

M4-DASH-02에서 사용할 Health Panel 후보는 다음과 같다.

Backend API:

- kube_deployment_status_replicas_available
- kube_deployment_status_replicas_unavailable
- kube_pod_status_ready
- kube_pod_container_status_restarts_total
- kube_pod_container_status_waiting_reason

AI Service:

- kube_deployment_status_replicas_available
- kube_deployment_status_replicas_unavailable
- kube_pod_status_ready
- kube_pod_container_status_restarts_total
- kube_pod_container_status_waiting_reason

Batch Worker:

- kube_deployment_status_replicas_available
- kube_pod_status_ready
- kube_pod_container_status_restarts_total
- kube_pod_container_status_waiting_reason
- SQS ApproximateNumberOfMessagesVisible
- SQS DLQ visible messages

## Alert 후보

M4-ALERT-01에서 사용할 Alert 후보는 다음과 같다.

Backend API:

- Deployment unavailable
- Pod NotReady 지속
- Pod restart 증가
- Container CrashLoopBackOff 또는 waiting reason 발생
- ALB UnHealthyHostCount 증가

AI Service:

- Deployment unavailable
- Pod NotReady 지속
- Pod restart 증가
- /health probe failure 지속
- Container CrashLoopBackOff 또는 waiting reason 발생

Batch Worker:

- Deployment unavailable
- Pod NotReady 지속
- Pod restart 증가
- Worker replica 0
- SQS visible messages 지속 증가
- DLQ messages 증가

## ALB Health Check와 Kubernetes Probe 관계

ALB Target Group Health Check와 Kubernetes Probe는 같은 목적이 아니다.

Kubernetes Probe:

- Pod가 트래픽을 받을 준비가 되었는지 확인
- Pod가 살아있는지 확인
- 실패 시 kubelet이 Pod 상태를 변경하거나 컨테이너를 재시작할 수 있음

ALB Target Group Health Check:

- ALB가 해당 Pod IP로 트래픽을 보낼 수 있는지 확인
- TargetGroup healthy / unhealthy 판단
- 외부 사용자 트래픽 라우팅 기준

Backend API는 /health가 401을 반환할 수 있으므로 ALB success-codes를 200,401로 둔다.
반면 Kubernetes Probe는 TCP 8080 기준으로 프로세스 listen 상태를 확인한다.

## Runtime 검증 기준

Runtime 리소스가 활성화되어 있을 때 다음을 확인한다.

Dev:

- kubectl get deploy -n moment-dev
- kubectl get pods -n moment-dev
- kubectl describe pod -n moment-dev <pod-name>
- kubectl get events -n moment-dev --sort-by=.lastTimestamp
- kubectl port-forward -n moment-dev svc/backend-api 8080:8080
- curl -i http://localhost:8080/health
- kubectl port-forward -n moment-dev svc/ai-service 8000:8000
- curl -i http://localhost:8000/health

Prod:

- Prod EKS와 Prod workload가 활성 상태인 경우 Dev와 동일 기준으로 확인한다.
- Prod가 비용 절감 또는 리소스 종료 상태인 경우 GitOps / Helm template 기준으로 정적 검증하고, Runtime 검증은 활성화 후 재수행한다.

## 정적 검증 기준

Runtime이 비활성 상태여도 다음은 검증한다.

- Backend API Dev Helm template에 readinessProbe / livenessProbe 렌더링
- Backend API Prod Helm template에 readinessProbe / livenessProbe 렌더링
- AI Service Dev Helm template에 readinessProbe / livenessProbe 렌더링
- AI Service Prod Helm template에 readinessProbe / livenessProbe 렌더링
- Batch Job Dev Helm template이 Deployment로 렌더링
- Batch Job Prod Helm template이 Deployment로 렌더링
- Batch Job Dev / Prod에 BATCH_SQS_CONSUMER_ENABLED=true 반영
- Batch Job Dev / Prod에 SPRING_BATCH_JOB_ENABLED=false 반영

## 결론

M4-HEALTH-01 기준에서 Backend API와 AI Service는 Kubernetes Probe 중심으로 관측한다.

Backend API는 TCP 8080 Probe와 ALB /health Health Check를 분리한다.

AI Service는 /health HTTP Probe를 사용한다.

Batch Job은 현재 CronJob이 아니라 SQS polling Worker Deployment이므로, HTTP Probe를 억지로 추가하지 않고 Deployment / Pod / Restart / SQS 상태 기준으로 관측한다.
