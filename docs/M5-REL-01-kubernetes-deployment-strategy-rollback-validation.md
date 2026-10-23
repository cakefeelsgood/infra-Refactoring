# [M5-REL-01] Kubernetes Deployment RollingUpdate / Rollback 정합성 검증 결과

## 1. 작업 개요

본 문서는 `[M5-REL-01] Kubernetes 배포 전략 / RollingUpdate / Rollback 정합성 검증 #685` 수행 결과를 정리한다.

검증 대상은 MoMent Kubernetes workload 중 GitOps로 배포되는 주요 Deployment이다.

- backend-api
- ai-service
- batch-job

이번 검증의 목적은 다음과 같다.

- Kubernetes Deployment 전략이 명시적으로 RollingUpdate로 관리되는지 확인
- Dev / Prod 환경의 replica 수, maxSurge, maxUnavailable 값이 환경 특성에 맞게 구성되어 있는지 확인
- readinessProbe / livenessProbe가 배포 안정성 관점에서 적절한지 확인
- GitOps 기반 rollback 기준을 문서화
- 실제 Dev / Prod live 환경에서 rollout, readiness, health check가 정상인지 확인
- 검증 중 발견된 NetworkPolicy egress 차단 문제를 우회 없이 GitOps 원본에서 근본 수정

## 2. 최종 결론

M5-REL-01은 최종적으로 완료 판정한다.

Dev와 Prod 모두 RollingUpdate 전략이 live Deployment에 정상 반영되었고, backend-api / ai-service / batch-job의 rollout 상태가 정상임을 확인했다.

또한 Dev 검증 중 backend-api가 CrashLoopBackOff에 빠지는 문제가 확인되었으나, 원인은 M5-REL-01의 RollingUpdate 변경 자체가 아니라 `network-policy-dev`의 default-deny egress 정책으로 인해 backend-api가 RDS PostgreSQL 5432에 접근하지 못한 것이었다.

해당 문제는 임시 kubectl patch가 아니라 `gitops/charts/network-policy` 및 Dev/Prod values를 수정하여 근본 해결했다.

최종 상태는 다음과 같다.

### Dev 최종 상태

- backend-api-dev: Synced
- ai-service-dev: Synced / Healthy
- batch-job-dev: Synced / Healthy
- network-policy-dev: Synced / Healthy
- backend-api Deployment: 1/1 Ready
- ai-service Deployment: 1/1 Ready
- batch-job Deployment: 1/1 Ready
- backend-api /health: HTTP 200
- backend-api Endpoint: 정상 생성
- backend-api RDS 연결: 정상
- Flyway migration: 정상
- HikariPool DB connection: 정상

### Prod 최종 상태

- backend-api-prod: Synced
- ai-service-prod: Synced / Healthy
- batch-job-prod: Synced / Healthy
- backend-api Deployment: 2/2 Ready
- ai-service Deployment: 2/2 Ready
- batch-job Deployment: 1/1 Ready
- backend-api rollout: successfully rolled out
- ai-service rollout: successfully rolled out
- batch-job rollout: successfully rolled out
- backend-api /health: HTTP 200

단, backend-api-prod ArgoCD Health는 Progressing으로 표시되었다. 이는 Deployment가 아니라 Ingress health 상태 영향으로 판단되며, Kubernetes Deployment RollingUpdate 정합성 범위에서는 blocker가 아니다. 별도 Edge / ALB / Ingress 상태 이슈로 분리 추적한다.

## 3. Git 변경 이력

최종 develop 기준 주요 커밋은 다음과 같다.

- `48ee999` `[ #685 ] Kubernetes RollingUpdate 배포 전략 및 rollback 정합성 보완`
- `2ab0ad5` `[ #685 ] NetworkPolicy data tier egress 정합성 보완`

작업 브랜치 및 후속 브랜치:

- `feature/kubernetes-deployment-strategy-rollback`
- `fix/networkpolicy-backend-data-egress`

## 4. 변경 파일

### RollingUpdate / Readiness / Scheduling 정합성 보완

- `docs/M5-REL-01-kubernetes-deployment-strategy-rollback-validation.md`
- `gitops/charts/batch-job/templates/deployment.yaml`
- `gitops/values/dev/backend-api-values.yaml`
- `gitops/values/prod/backend-api-values.yaml`
- `gitops/values/dev/ai-service-values.yaml`
- `gitops/values/prod/ai-service-values.yaml`

### NetworkPolicy egress 근본 보완

- `gitops/charts/network-policy/values.yaml`
- `gitops/charts/network-policy/templates/allow-data-tier-egress.yaml`
- `gitops/charts/network-policy/templates/allow-service-egress.yaml`
- `gitops/values/dev/network-policy-values.yaml`
- `gitops/values/prod/network-policy-values.yaml`

## 5. RollingUpdate 전략 최종 상태

### Dev

Dev는 비용과 최소 리소스 기준으로 replica 1 기반 검증 환경이다.

| Workload | Replicas | Strategy | maxSurge | maxUnavailable |
|---|---:|---|---:|---:|
| backend-api | 1 | RollingUpdate | 1 | 1 |
| ai-service | 1 | RollingUpdate | 1 | 1 |
| batch-job | 1 | RollingUpdate | 1 | 1 |

Dev live 확인 결과:

- backend-api: replicas=1, ready=1, updated=1, available=1
- ai-service: replicas=1, ready=1, updated=1, available=1
- batch-job: replicas=1, ready=1, updated=1, available=1

### Prod

Prod는 사용자 트래픽 영향 최소화를 위해 API 계열은 무중단 기준으로 설정했다.

| Workload | Replicas | Strategy | maxSurge | maxUnavailable |
|---|---:|---|---:|---:|
| backend-api | 2 | RollingUpdate | 1 | 0 |
| ai-service | 2 | RollingUpdate | 1 | 0 |
| batch-job | 1 | RollingUpdate | 1 | 1 |

Prod live 확인 결과:

- backend-api: replicas=2, ready=2, updated=2, available=2
- ai-service: replicas=2, ready=2, updated=2, available=2
- batch-job: replicas=1, ready=1, updated=1, available=1

## 6. Probe 정합성

### backend-api

기존 backend-api readinessProbe는 tcpSocket 기반으로 포트 오픈만 확인하는 구조였다.

하지만 실무적으로 backend-api는 DB 연결, Flyway, JPA 초기화 등 주요 의존성이 정상이어야 실제 요청을 받을 수 있다. 단순 TCP 포트 확인은 애플리케이션 준비 상태를 충분히 검증하지 못한다.

따라서 readinessProbe를 HTTP `/health` 기반으로 보완했다.

최종 live 상태:

- readinessProbe: `/health:8080`
- livenessProbe: `tcp:8080`

Dev와 Prod 모두 `/health`가 HTTP 200을 반환함을 확인했다.

## 7. batch-job RollingUpdate 렌더링 누락 보완

검증 과정에서 batch-job chart의 values에는 strategy가 정의되어 있었으나, Deployment template에서 `.Values.strategy`를 렌더링하지 않는 문제가 확인되었다.

그 결과 live batch-job Deployment는 Kubernetes 기본값인 `maxSurge=25%`, `maxUnavailable=25%`로 동작하고 있었다.

수정 내용:

- `gitops/charts/batch-job/templates/deployment.yaml`에 `.Values.strategy` 렌더링 추가

수정 후 결과:

- Dev batch-job: `maxSurge=1`, `maxUnavailable=1`
- Prod batch-job: `maxSurge=1`, `maxUnavailable=1`

## 8. ai-service anti-affinity 보완

Prod ai-service는 replica 2로 운영되지만, 검증 당시 두 Pod가 같은 노드에 배치될 수 있는 구조였다.

다만 현재 Prod에서 ai node pool이 제한적인 상태이므로 required anti-affinity를 적용하면 Pending 위험이 있다.

따라서 required가 아닌 preferred anti-affinity를 적용했다.

적용 기준:

- hostname 기준 preferred anti-affinity weight 100
- zone 기준 preferred anti-affinity weight 50

이 방식은 가용성 힌트를 제공하면서도, 노드 수가 부족할 때 스케줄링 실패를 만들지 않는다.

## 9. Rollback 기준

본 프로젝트는 ArgoCD GitOps 기반 운영을 전제로 한다.

따라서 rollback의 원칙은 Kubernetes live object를 직접 되돌리는 것이 아니라 Git desired state를 되돌리는 것이다.

### 정식 rollback 방식

- Git revert
- image tag rollback
- Helm values rollback
- ArgoCD sync

### 비권장 방식

- `kubectl rollout undo`
- live Deployment 직접 patch
- kubectl edit
- 임시 manifest apply

`kubectl rollout undo`는 긴급 상황에서 containment 용도로만 사용할 수 있으며, 최종 상태는 반드시 GitOps desired state와 일치시켜야 한다.

## 10. NetworkPolicy egress blocker

### 10.1 현상

M5-REL-01 post-merge Dev live 검증 중 backend-api가 `0/1` 상태로 유지되었고, Pod는 CrashLoopBackOff 상태였다.

backend-api 로그에서는 다음 흐름이 확인되었다.

- Spring Boot 기동
- Tomcat 8080 초기화
- Flyway 초기화 진입
- RDS PostgreSQL connection timeout
- ApplicationContext 초기화 실패
- 컨테이너 종료
- CrashLoopBackOff

### 10.2 최초 오해 가능성

초기에는 다음 가능성을 확인했다.

- ALB / Ingress 문제
- RDS 상태 문제
- RDS Security Group 문제
- Node Security Group 문제
- DNS 문제
- Route Table / NACL 문제

검증 결과:

- RDS는 available 상태
- RDS endpoint DNS resolve 정상
- RDS SG는 EKS node SG를 허용
- Node SG egress 허용
- NACL은 allow-all 성격
- DNS 조회 정상

하지만 Pod에서 RDS 5432 TCP 연결은 timeout 되었다.

### 10.3 근본 원인

근본 원인은 `network-policy-dev`였다.

기존 Dev namespace에는 `default-deny-all` NetworkPolicy가 존재했다.

정책 내용:

- podSelector: {}
- policyTypes:
  - Ingress
  - Egress

즉 namespace 전체 Pod의 Ingress / Egress를 기본 차단하는 정책이다.

기존 허용 정책 중 egress는 DNS만 열려 있었다.

- allow-dns-egress: TCP/UDP 53

반면 backend-api가 RDS PostgreSQL 5432로 나갈 수 있는 egress 정책은 없었다.

따라서 backend-api는 DNS resolve는 가능했지만, RDS 5432 TCP 연결은 timeout 되었다.

### 10.4 근본 해결

임시 kubectl patch를 사용하지 않고, GitOps 원본을 수정했다.

network-policy chart를 values-driven 구조로 변경하고 다음 egress policy를 추가했다.

- allow-backend-api-data-tier-egress
- allow-batch-job-data-tier-egress
- allow-ai-service-data-tier-egress
- allow-backend-api-to-ai-service-egress
- allow-ai-service-to-backend-api-egress

Dev data tier CIDR:

- 10.20.20.0/24
- 10.20.21.0/24

Prod data tier CIDR:

- 10.10.20.0/24
- 10.10.21.0/24

Workload별 허용:

### backend-api

- data tier TCP 5432
- data tier TCP 6379
- data tier TCP 443
- ai-service TCP 8000

### batch-job

- data tier TCP 5432
- data tier TCP 443

### ai-service

- data tier TCP 443
- backend-api TCP 8080

### 10.5 NetworkPolicy 검증 방식

기존 netshoot Pod는 라벨이 `run=netshoot`였기 때문에 backend-api용 egress policy 대상이 아니었다.

따라서 기존 netshoot에서 RDS 5432 연결이 timeout 되는 것은 정상이다.

정확한 검증을 위해 backend-api와 동일한 label을 가진 검증용 Pod를 생성했다.

검증용 Pod label:

- `app.kubernetes.io/name=backend-api`
- `app.kubernetes.io/instance=backend-api-dev`
- `environment=dev`

검증 결과:

- DNS resolve 정상
- RDS PostgreSQL 5432 TCP 연결 성공

이후 기존 CrashLoopBackOff backend-api Pod를 삭제하여 ReplicaSet이 새 Pod를 생성하게 했고, 새 Pod는 정상 기동했다.

최종 확인:

- Flyway DB 연결 성공
- Flyway migration validation 성공
- HikariPool DB connection 생성 성공
- Spring Boot started
- `/health` HTTP 200
- backend-api Deployment 1/1 Ready
- backend-api Pod 1/1 Running
- Restart Count 0

## 11. Dev 최종 검증 결과

### ArgoCD App

| App | Sync | Health | Revision |
|---|---|---|---|
| backend-api-dev | Synced | Progressing | 2ab0ad5 |
| ai-service-dev | Synced | Healthy | 2ab0ad5 |
| batch-job-dev | Synced | Healthy | 2ab0ad5 |
| network-policy-dev | Synced | Healthy | 2ab0ad5 |

backend-api-dev의 App Health는 Progressing으로 표시되었으나, Deployment와 Pod는 정상 상태이고 `/health`가 200을 반환했다.

### Deployment

| Deployment | Ready | Image |
|---|---|---|
| backend-api | 1/1 | moment-dev-backend-api:dev-4592913 |
| ai-service | 1/1 | moment-dev-ai-service:dev-62e003b |
| batch-job | 1/1 | moment-dev-batch-job:dev-4592913 |

### Rollout

- backend-api: successfully rolled out
- ai-service: successfully rolled out
- batch-job: successfully rolled out

### Health Check

- backend-api `/health`: HTTP 200
- Body: `MoMent backend is running`

## 12. Prod 수동 sync 검증 결과

Dev에서 정상화가 확인된 후 Prod는 자동 sync가 아니라 수동 sync로 통제하여 반영했다.

반영 순서:

1. ai-service-prod
2. batch-job-prod
3. backend-api-prod

### Sync 전 Diff

ai-service-prod:

- preferred podAntiAffinity 추가

batch-job-prod:

- maxSurge: 25% -> 1
- maxUnavailable: 25% -> 1

backend-api-prod:

- readinessProbe에 HTTP GET `/health:8080` 추가

### ArgoCD App 최종 상태

| App | Sync | Health | Revision |
|---|---|---|---|
| ai-service-prod | Synced | Healthy | 2ab0ad5 |
| batch-job-prod | Synced | Healthy | 2ab0ad5 |
| backend-api-prod | Synced | Progressing | 2ab0ad5 |

backend-api-prod Health가 Progressing인 이유는 Ingress 리소스가 Progressing 상태이기 때문으로 판단된다. Deployment / Service / HPA / PDB는 정상이다.

### Deployment 최종 상태

| Deployment | Ready | Image |
|---|---|---|
| backend-api | 2/2 | moment-prod-backend-api:prod-4592913 |
| ai-service | 2/2 | moment-prod-ai-service:prod-62e003b |
| batch-job | 1/1 | moment-prod-batch-job:prod-22d7c4e |

### Rollout

- backend-api: successfully rolled out
- ai-service: successfully rolled out
- batch-job: successfully rolled out

### Endpoint

backend-api endpoint:

- 10.10.11.204:8080
- 10.10.11.97:8080

### Health Check

- backend-api `/health`: HTTP 200
- Body: `MoMent backend is running`

## 13. Prod 주의 사항

### 13.1 backend-api-prod App Health Progressing

backend-api-prod는 App Health가 Progressing으로 표시된다.

다만 다음은 정상이다.

- Deployment 2/2 Ready
- Pod 2개 Running
- Service Healthy
- HPA Healthy
- PDB Healthy
- `/health` HTTP 200
- Endpoint 정상 생성

따라서 이는 Deployment RollingUpdate 문제라기보다 Ingress / ALB / Edge 경로 상태 문제로 분리한다.

### 13.2 과거 Error Pod 잔존

Prod Pod 목록에 과거 backend-api Error Pod가 남아 있었다.

하지만 현재 Deployment는 2/2 Ready이고, Endpoint는 새 Running Pod 2개만 포함하고 있다.

따라서 서비스 트래픽에는 영향이 없다.

필요 시 별도 housekeeping으로 정리할 수 있으나, M5-REL-01의 배포 전략 정합성 blocker는 아니다.

### 13.3 network-policy-prod Application 부재

Prod에는 현재 `network-policy-prod` Application이 존재하지 않는다.

이번 #685 후속에서는 network-policy chart와 prod values까지 정합성을 보완했지만, Prod live에 network-policy-prod 앱을 신규 생성하지는 않았다.

이는 의도적으로 범위를 제한한 것이다.

Prod NetworkPolicy를 실제로 운영할지는 별도 이슈에서 다음 항목을 검토해야 한다.

- Prod namespace default-deny 적용 여부
- backend-api / batch-job / ai-service data-tier egress 허용
- ALB / monitoring / external service egress
- rollout 순서
- 장애 복구 계획

## 14. 최종 판정

M5-REL-01의 핵심 검증 항목은 완료되었다.

### 완료된 항목

- Dev RollingUpdate 전략 확인
- Prod RollingUpdate 전략 확인
- batch-job strategy 렌더링 누락 수정
- backend-api readinessProbe `/health` 전환
- ai-service preferred anti-affinity 적용
- GitOps 기반 rollback 원칙 문서화
- Dev backend NetworkPolicy egress blocker 근본 해결
- Dev live rollout 및 health check 성공
- Prod 수동 sync 및 rollout 성공
- Prod backend `/health` 200 확인

### 별도 추적 항목

- backend-api-prod ArgoCD Health Progressing 원인인 Ingress / ALB 상태
- Prod network-policy-prod Application 도입 여부
- 과거 Error Pod housekeeping

## 15. 운영 기준

향후 유사한 배포 전략 검증 시 다음 기준을 따른다.

- default-deny NetworkPolicy 적용 시 workload별 egress를 반드시 함께 정의한다.
- netshoot 등 검증용 Pod는 실제 NetworkPolicy podSelector와 동일한 label을 사용해 검증한다.
- readinessProbe는 단순 port open보다 애플리케이션 실제 준비 상태를 반영해야 한다.
- Prod sync는 자동보다 수동 sync로 단계별 반영하고, 앱별 rollout 및 health를 확인한다.
- rollback은 GitOps desired state 기준으로 수행한다.
- kubectl patch / kubectl edit / rollout undo는 최종 해결 방식으로 사용하지 않는다.

## 16. Evidence 경로

### Dev

- `tmp/m5-rel-01-final-dev-evidence-after-networkpolicy-20260611-002614/M5-REL-01-final-dev-evidence-after-networkpolicy.txt`

### Prod

- `tmp/m5-rel-01-prod-manual-sync-20260611-002745/M5-REL-01-prod-manual-sync.txt`

### NetworkPolicy root fix

- `tmp/m5-rel-01-networkpolicy-root-fix-20260611-001535/step-02-networkpolicy-root-fix.txt`
- `tmp/m5-rel-01-networkpolicy-root-fix-verify-20260611-001619/step-03-networkpolicy-root-fix-verify.txt`
- `tmp/m5-rel-01-networkpolicy-backend-label-test-20260611-002203/step-06-backend-label-egress-test.txt`
- `tmp/m5-rel-01-backend-recovery-after-networkpolicy-20260611-002339/step-07-backend-recovery-after-networkpolicy.txt`
