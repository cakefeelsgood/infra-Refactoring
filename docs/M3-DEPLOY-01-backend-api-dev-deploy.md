# M3-DEPLOY-01 Backend API Dev 배포 검증 문서

## 1. 작업 개요

M3-DEPLOY-01에서는 Backend API를 Dev EKS 환경에 배포하고, GitOps/ArgoCD/Helm/ALB 기반 배포 흐름이 정상 동작하는지 검증하였다.

최종적으로 Backend API는 `moment-dev` namespace에 배포되었고, ArgoCD Application은 `Synced / Healthy` 상태를 확인하였다. Backend API Pod는 `1/1 Running` 상태이며, Service / Endpoint / Ingress / ALB / TargetGroup까지 정상 연결되었다.

---

## 2. GitOps / Helm 경로

| 구분                                 | 경로                                                    |
| ---------------------------------- | ----------------------------------------------------- |
| Backend API Helm Chart             | `gitops/charts/backend-api`                           |
| Backend API Dev values             | `gitops/values/dev/backend-api-values.yaml`           |
| Backend API Prod values            | `gitops/values/prod/backend-api-values.yaml`          |
| Backend API Dev ArgoCD Application | `gitops/argocd/dev/applications/backend-api-dev.yaml` |

---

## 3. ArgoCD Application 정보

| 구분                    | 값                                          |
| --------------------- | ------------------------------------------ |
| Application name      | `backend-api-dev`                          |
| Namespace             | `argocd`                                   |
| Destination namespace | `moment-dev`                               |
| Source chart path     | `gitops/charts/backend-api`                |
| Dev values path       | `../../values/dev/backend-api-values.yaml` |

Prod Application은 비용 및 운영 승인 전 상태로 실제 배포 검증 대상에서 제외하고, 후속 이슈에서 처리한다.

---

## 4. Dev 배포 검증 결과

아래 항목을 확인하였다.

* Backend API Deployment `1/1` 확인
* Backend API Pod `1/1 Running` 확인
* Backend API Service 생성 확인
* Backend API Endpoint / EndpointSlice 생성 확인
* Endpoint에 Ready Pod IP 연결 확인
* Ingress ADDRESS 생성 확인
* AWS Load Balancer Controller reconcile 성공
* ALB `active` 상태 확인
* TargetGroup `healthy` 상태 확인
* ArgoCD Application `Synced / Healthy` 확인

---

## 5. 최종 확인 명령어

### ArgoCD 상태 확인

```bash
kubectl get application backend-api-dev -n argocd
```

기대 결과:

```text
backend-api-dev   Synced   Healthy
```

### Kubernetes 리소스 확인

```bash
kubectl get deploy backend-api -n moment-dev
kubectl get pod -n moment-dev -l app.kubernetes.io/name=backend-api
kubectl get svc backend-api -n moment-dev
kubectl get endpoints backend-api -n moment-dev -o wide
kubectl get ingress backend-api -n moment-dev
```

기대 결과:

```text
Deployment: 1/1
Pod: 1/1 Running
Endpoint: Pod IP:8080 연결
Ingress: ALB DNS ADDRESS 생성
```

### ALB 상태 확인

```bash
aws elbv2 describe-load-balancers \
  --region ap-northeast-3 \
  --query "LoadBalancers[?contains(LoadBalancerName, 'k8s-momentde')].[LoadBalancerName,DNSName,State.Code]" \
  --output table
```

기대 결과:

```text
State.Code = active
```

### TargetGroup Health 확인

```bash
aws elbv2 describe-target-health \
  --region ap-northeast-3 \
  --target-group-arn "$TG_ARN" \
  --query "TargetHealthDescriptions[*].{Target:Target.Id,Port:Target.Port,State:TargetHealth.State,Reason:TargetHealth.Reason,Description:TargetHealth.Description}" \
  --output table
```

기대 결과:

```text
State = healthy
Reason = None
Description = None
```

---

## 6. 런타임 설정 정리

Backend API 기동 중 아래 런타임 설정 누락 문제가 발생했으며, 최종적으로 GitOps values에 반영하였다.

* DB / Flyway 연결 URL
* DB / Flyway username, password Secret reference
* JWT Secret reference
* Kakao OAuth runtime env
* SQS queue runtime env
* Public Data API runtime env
* Spring Batch schema 초기화 설정
* TCP 기반 readiness / liveness probe
* ALB health check success codes `200,401`

`/health` 요청은 현재 Spring Security 정책상 401을 반환할 수 있으므로, ALB TargetGroup health check는 `alb.ingress.kubernetes.io/success-codes: "200,401"` 기준으로 처리하였다.

---

## 7. 장애 대응 기록

이번 배포 중 확인한 주요 장애와 처리 내용은 다음과 같다.

| 문제                                | 원인                                           | 처리                                                                                |
| --------------------------------- | -------------------------------------------- | --------------------------------------------------------------------------------- |
| Pod CrashLoopBackOff              | `DB_URL` 누락                                  | Dev values에 DB URL 추가                                                             |
| DB connection timeout             | RDS SG에서 EKS node SG 접근 미허용                  | RDS SG 5432 ingress 허용                                                            |
| DB password authentication failed | Kubernetes Secret의 DB password 불일치           | RDS Secret 기준으로 Kubernetes Secret 재생성                                             |
| JWT Base64 오류                     | JWT secret 형식 불일치                            | Base64 형식 JWT secret 사용                                                           |
| Kakao placeholder 오류              | Kakao runtime env 누락                         | Kakao env 추가                                                                      |
| SQS placeholder 오류                | SQS queue URL env 누락                         | SQS env 추가                                                                        |
| Public Data placeholder 오류        | 공공데이터 API key env 누락                         | Public Data env 추가                                                                |
| Batch table 오류                    | Spring Batch metadata table 미생성              | `SPRING_BATCH_JDBC_INITIALIZE_SCHEMA=always`, `SPRING_BATCH_JOB_ENABLED=false` 적용 |
| Pod 0/1 반복                        | `/health` HTTP probe와 Spring Security 401 응답 | TCP probe로 변경                                                                     |
| TargetGroup unhealthy             | `/health` 401 ResponseCodeMismatch           | ALB success-codes `200,401` 적용                                                    |
| ALB 미생성                           | EKS 재생성 후 ALB Controller IRSA OIDC trust 불일치 | ALB Controller trust policy를 신규 OIDC로 갱신                                          |

---

## 8. 보안 검증

아래 Secret 값은 Git에 평문으로 포함하지 않고 Kubernetes Secret reference로 처리하였다.

* DB username
* DB password
* JWT secret
* Toss secret

values 파일에는 DB password, JWT secret, Toss secret, AWS credential, kubeconfig를 포함하지 않는다.

---

## 9. Prod 관련 처리

Prod 관련 검증 항목은 비용 및 운영 승인 전 상태로 실제 배포를 수행하지 않았다.

Prod 관련 항목은 후속 이슈에서 처리한다.

* M3-ARGO-03 Prod ArgoCD 설치 및 Prod Application 구성
* M3-PROMOTE-01 Dev 검증 image tag Prod 승격 및 rollback 전략 구성

---

## 10. M3-PROMOTE-01 인수인계 기준

| 항목                           | 값                                            |
| ---------------------------- | -------------------------------------------- |
| Dev 검증 Backend API image tag | `dev-24eabd0`                                |
| Backend API Dev values path  | `gitops/values/dev/backend-api-values.yaml`  |
| Backend API Prod values path | `gitops/values/prod/backend-api-values.yaml` |
| Backend API Dev Application  | `backend-api-dev`                            |
| Backend API Prod Application | `backend-api-prod`                           |

M3-PROMOTE-01에서는 Dev에서 검증된 image tag를 기준으로 Prod values 승격 여부를 판단한다.

---

## 11. 최종 결론

M3-DEPLOY-01 Backend API Dev 배포 구성 및 검증을 완료하였다.

* ArgoCD `Synced / Healthy`
* Backend API Deployment `1/1`
* Backend API Pod `1/1 Running`
* Service / Endpoint 연결 완료
* Ingress ADDRESS 생성 완료
* ALB active 확인
* TargetGroup healthy 확인

Prod 관련 검증은 비용 및 운영 승인 전 상태로 blocker 처리하고 후속 이슈에서 진행한다.
